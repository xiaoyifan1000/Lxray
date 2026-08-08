//go:build android

package tun

import (
	"context"
	"errors"
	"os"
	"strconv"
	_ "unsafe"

	"github.com/xtls/xray-core/common/buf"
	xerrors "github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/platform"
	"golang.org/x/sys/unix"
	"gvisor.dev/gvisor/pkg/buffer"
	"gvisor.dev/gvisor/pkg/tcpip"
	"gvisor.dev/gvisor/pkg/tcpip/stack"
)

//go:linkname procyield runtime.procyield
func procyield(cycles uint32)

// AndroidTun 直接对系统授予的 tun fd 做 read/write,
// 不经过 gvisor fdbased(其 isSocketFD 会调用 fstat,
// 鸿蒙内核对 tun fd 的 fstat 返回 EPERM)
type AndroidTun struct {
	tunFd   int
	tunFile *os.File
	options TunOptions
}

var _ Tun = (*AndroidTun)(nil)
var _ GVisorTun = (*AndroidTun)(nil)
var _ GVisorDevice = (*AndroidTun)(nil)

// NewTun builds new tun interface handler
func NewTun(options TunOptions) (Tun, error) {
	fd, err := strconv.Atoi(platform.NewEnvFlag(platform.TunFdKey).GetValue(func() string { return "0" }))
	xerrors.LogInfo(context.Background(), "read Android Tun Fd ", fd, err)
	if err != nil {
		return nil, err
	}
	if fd <= 0 {
		return nil, xerrors.New("invalid tun fd: ", fd)
	}

	if err = unix.SetNonblock(fd, true); err != nil {
		_ = unix.Close(fd)
		return nil, err
	}

	return &AndroidTun{
		tunFd:   fd,
		tunFile: os.NewFile(uintptr(fd), "vpn-tun"),
		options: options,
	}, nil
}

func (t *AndroidTun) Start() error {
	return nil
}

func (t *AndroidTun) Close() error {
	return nil
}

// newEndpoint 使用 xray 自带的 LinkEndpoint(无 fstat), 本对象即 GVisorDevice
func (t *AndroidTun) newEndpoint() (stack.LinkEndpoint, error) {
	return &LinkEndpoint{
		deviceMTU: t.options.MTU,
		device:    t,
	}, nil
}

// WritePacket implements GVisorDevice method to write one packet to the tun device
func (t *AndroidTun) WritePacket(packet *stack.PacketBuffer) tcpip.Error {
	b := buf.NewWithSize(int32(t.options.MTU))
	defer b.Release()

	for _, packetElement := range packet.AsSlices() {
		_, _ = b.Write(packetElement)
	}

	if _, err := t.tunFile.Write(b.Bytes()); err != nil {
		if errors.Is(err, unix.EAGAIN) {
			return &tcpip.ErrWouldBlock{}
		}
		return &tcpip.ErrAborted{}
	}
	return nil
}

// ReadPacket implements GVisorDevice method to read one packet from the tun device
func (t *AndroidTun) ReadPacket() (byte, *stack.PacketBuffer, error) {
	b := buf.NewWithSize(int32(t.options.MTU))

	n, err := b.ReadFrom(t.tunFile)
	if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EINTR) {
		b.Release()
		return 0, nil, ErrQueueEmpty
	}
	if err != nil {
		b.Release()
		return 0, nil, err
	}
	if n <= 0 {
		b.Release()
		return 0, nil, ErrQueueEmpty
	}

	version := b.Byte(0) >> 4
	packetBuffer := buffer.MakeWithData(b.Bytes())
	return version, stack.NewPacketBuffer(stack.PacketBufferOptions{
		Payload:           packetBuffer,
		IsForwardedPacket: true,
		OnRelease: func() {
			b.Release()
		},
	}), nil
}

// Wait some cpu cycles
func (t *AndroidTun) Wait() {
	procyield(1)
}
