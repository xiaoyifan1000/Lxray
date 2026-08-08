/*
 * OutboundGenerator.ets - 节点信息 → xray outbound JSON 生成
 *
 * 生成 vless + reality/tls + tcp/ws/grpc 的 outbound 结构,
 * 与 xray-core 26.x 配置格式对齐; 未覆盖的传输参数按节点字段透传
 */
import { VlessNode } from './parser/VlessParser';

export interface VlessUser {
  id: string;
  encryption: string;
  flow?: string;
}

export interface VlessServer {
  address: string;
  port: number;
  users: VlessUser[];
}

export interface VlessSettings {
  vnext: VlessServer[];
}

export interface VmessSettings {
  vnext: VmessServer[];
}

export interface VmessServer {
  address: string;
  port: number;
  users: VmessUser[];
}

export interface VmessUser {
  id: string;
  alterId: number;
  security: string;
}

export interface RealitySettings {
  serverName: string;
  fingerprint: string;
  publicKey: string;
  shortId: string;
}

export interface TlsSettings {
  serverName: string;
  fingerprint?: string;
}

export interface WsSettings {
  path?: string;
  host?: string;
}

export interface GrpcSettings {
  serviceName?: string;
}

export interface StreamSettings {
  network: string;
  security: string;
  realitySettings?: RealitySettings;
  tlsSettings?: TlsSettings;
  wsSettings?: WsSettings;
  grpcSettings?: GrpcSettings;
}

export interface MuxSettings {
  enabled: boolean;
  concurrency: number;
}

export interface Outbound {
  tag: string;
  protocol: string;
  settings: VlessSettings | VmessSettings;
  streamSettings: StreamSettings;
  mux: MuxSettings;
}

export namespace OutboundGenerator {

  export function buildProxy(node: VlessNode): Outbound {
    const stream = buildStream(node);
    if (node.protocol === 'vmess') {
      const vmessUser: VmessUser = {
        id: node.uuid,
        alterId: 0,
        security: node.encryption.length > 0 ? node.encryption : 'auto'
      };
      const vmessServer: VmessServer = {
        address: node.address,
        port: node.port,
        users: [vmessUser]
      };
      const settings: VmessSettings = { vnext: [vmessServer] };
      const outbound: Outbound = {
        tag: 'proxy',
        protocol: 'vmess',
        settings: settings,
        streamSettings: stream,
        mux: { enabled: false, concurrency: -1 }
      };
      return outbound;
    }
    const user: VlessUser = {
      id: node.uuid,
      encryption: node.encryption.length > 0 ? node.encryption : 'none'
    };
    if (node.flow.length > 0) {
      user.flow = node.flow;
    }
    const server: VlessServer = {
      address: node.address,
      port: node.port,
      users: [user]
    };
    const settings: VlessSettings = { vnext: [server] };
    const outbound: Outbound = {
      tag: 'proxy',
      protocol: 'vless',
      settings: settings,
      streamSettings: stream,
      mux: { enabled: false, concurrency: -1 }
    };
    return outbound;
  }

  function buildStream(node: VlessNode): StreamSettings {
    const stream: StreamSettings = {
      network: node.network.length > 0 ? node.network : 'tcp',
      security: node.security
    };
    if (node.security === 'reality') {
      const reality: RealitySettings = {
        serverName: node.sni,
        fingerprint: node.fingerprint.length > 0 ? node.fingerprint : 'chrome',
        publicKey: node.publicKey,
        shortId: node.shortId
      };
      stream.realitySettings = reality;
    } else if (node.security === 'tls') {
      const tls: TlsSettings = { serverName: node.sni };
      if (node.fingerprint.length > 0) {
        tls.fingerprint = node.fingerprint;
      }
      stream.tlsSettings = tls;
    }
    if (node.network === 'ws') {
      const ws: WsSettings = {};
      if (node.path.length > 0) {
        ws.path = node.path;
      }
      if (node.host.length > 0) {
        ws.host = node.host;
      }
      stream.wsSettings = ws;
    } else if (node.network === 'grpc') {
      const grpc: GrpcSettings = {};
      if (node.path.length > 0) {
        grpc.serviceName = node.path;
      }
      stream.grpcSettings = grpc;
    }
    return stream;
  }
}
