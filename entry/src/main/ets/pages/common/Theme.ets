/*
 * Theme.ets - 全局视觉主题(深色)
 * 色板/字号/圆角/间距统一出处, 改风格只动这里
 */
export class AppTheme {
  static readonly BG_PAGE: string = '#0D1321';
  static readonly BG_CARD: string = '#171F33';
  static readonly BG_CARD_HOVER: string = '#1E2942';
  static readonly BG_INPUT: string = '#111A2E';
  static readonly ACCENT: string = '#4F7CFF';
  static readonly ACCENT_GRADIENT_START: string = '#4F7CFF';
  static readonly ACCENT_GRADIENT_END: string = '#7B5CFF';
  static readonly SUCCESS: string = '#2BD98F';
  static readonly WARNING: string = '#F5B94F';
  static readonly DANGER: string = '#F26D6D';
  static readonly TEXT_PRIMARY: string = '#F2F5FA';
  static readonly TEXT_SECONDARY: string = '#8B96AD';
  static readonly TEXT_HINT: string = '#55617A';
  static readonly DIVIDER: string = '#232D45';
  static readonly RADIUS_SM: number = 8;
  static readonly RADIUS_MD: number = 14;
  static readonly RADIUS_LG: number = 20;
  static readonly SPACE_SM: number = 8;
  static readonly SPACE_MD: number = 14;
  static readonly SPACE_LG: number = 22;
}

export function levelColor(level: number): string {
  if (level >= 6) {
    return AppTheme.DANGER;
  }
  if (level === 5) {
    return AppTheme.WARNING;
  }
  if (level === 4) {
    return AppTheme.TEXT_SECONDARY;
  }
  return AppTheme.TEXT_HINT;
}
