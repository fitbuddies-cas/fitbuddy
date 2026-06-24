// FitBuddy design atoms — shared tokens and primitives
// All screens import these via window globals.

const FB = {
  // surfaces
  bg: '#F2F1ED',          // canvas (off-white, warm)
  card: '#FFFFFF',
  cardSubtle: '#F8F7F4',
  // ink
  ink: '#0E0E0E',
  ink2: '#3C3C43',
  muted: '#8A8A8E',
  ter: 'rgba(60,60,67,0.30)',
  border: 'rgba(60,60,67,0.10)',
  divider: 'rgba(60,60,67,0.08)',
  // accents
  accent: 'oklch(0.62 0.14 150)',
  accentInk: '#0E2F1F',
  accentSoft: 'oklch(0.95 0.04 150)',
  accentBorder: 'oklch(0.85 0.06 150)',
  warn: 'oklch(0.66 0.16 55)',
  warnSoft: 'oklch(0.96 0.04 65)',
  red: '#E5484D',
  redSoft: '#FFEFEF',
  // type
  font: '-apple-system, "SF Pro Text", system-ui, sans-serif',
  fontMono: '"SF Mono", ui-monospace, "Menlo", monospace',
};

// Dark-mode palette. Warm charcoal surfaces echo the light off-white; accents
// are lightened so they keep contrast on a dark background. Mirrors the dark
// appearances in the iOS DesignSystem.xcassets color sets.
const FB_DARK = {
  // surfaces
  bg: '#1A1815',
  card: '#262320',
  cardSubtle: '#302C28',
  // ink
  ink: '#F2F1ED',
  ink2: '#B5B2A8',
  muted: '#8E8B85',
  ter: 'rgba(235,235,245,0.30)',
  border: 'rgba(255,255,255,0.12)',
  divider: 'rgba(255,255,255,0.08)',
  // accents
  accent: '#55B66E',
  accentInk: '#BCDFC6',
  accentSoft: '#18271D',
  accentBorder: '#2C4F38',
  warn: '#E98B3A',
  warnSoft: '#2A2117',
  red: '#FF5A60',
  redSoft: '#2E1A1B',
};

// ─── Layout ────────────────────────────────────────────────────────────
function FBScreen({ children, padding = '0 16px', bg = FB.bg, dark = false }) {
  return (
    <div style={{
      minHeight: '100%', background: bg, padding,
      fontFamily: FB.font, color: dark ? '#fff' : FB.ink,
      WebkitFontSmoothing: 'antialiased',
    }}>{children}</div>
  );
}

function FBNav({ title, sub, trailing, large = false }) {
  return (
    <div style={{ paddingTop: 56, paddingBottom: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', minHeight: 32 }}>
        <div style={{
          fontSize: 13, fontWeight: 500, letterSpacing: 0.6,
          color: FB.muted, textTransform: 'uppercase',
        }}>{sub}</div>
        {trailing}
      </div>
      <div style={{
        fontSize: large ? 34 : 28, fontWeight: 700, letterSpacing: -0.6,
        marginTop: 4, lineHeight: 1.1,
      }}>{title}</div>
    </div>
  );
}

// ─── Buttons ───────────────────────────────────────────────────────────
function FBButton({ children, kind = 'primary', disabled = false, onClick, style = {}, fullWidth = true }) {
  const styles = {
    primary: { background: FB.ink, color: '#fff' },
    accent: { background: FB.accent, color: '#fff' },
    secondary: { background: FB.cardSubtle, color: FB.ink, boxShadow: `inset 0 0 0 1px ${FB.border}` },
    ghost: { background: 'transparent', color: FB.ink, boxShadow: `inset 0 0 0 1px ${FB.border}` },
    danger: { background: FB.redSoft, color: FB.red, boxShadow: `inset 0 0 0 1px ${FB.red}33` },
  }[kind];
  return (
    <button onClick={disabled ? undefined : onClick} disabled={disabled} style={{
      width: fullWidth ? '100%' : 'auto', height: 52, borderRadius: 14,
      border: 'none', fontFamily: FB.font, fontSize: 17, fontWeight: 600,
      letterSpacing: -0.2, cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.4 : 1,
      transition: 'transform 120ms ease, opacity 120ms ease',
      ...styles, ...style,
    }}>{children}</button>
  );
}

// ─── Card primitives ───────────────────────────────────────────────────
function FBCard({ children, style = {}, pad = 16 }) {
  return (
    <div style={{
      background: FB.card, borderRadius: 18, padding: pad,
      boxShadow: `0 0 0 1px ${FB.border}`,
      ...style,
    }}>{children}</div>
  );
}

function FBLabel({ children, style = {} }) {
  return (
    <div style={{
      fontSize: 12, fontWeight: 500, letterSpacing: 0.6,
      color: FB.muted, textTransform: 'uppercase', ...style,
    }}>{children}</div>
  );
}

// ─── Stats ─────────────────────────────────────────────────────────────
function FBStat({ label, value, unit, delta, deltaKind = 'pos' }) {
  const deltaColor = deltaKind === 'pos' ? FB.accent : deltaKind === 'neg' ? FB.red : FB.muted;
  return (
    <div>
      <FBLabel>{label}</FBLabel>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 6 }}>
        <span style={{
          fontFamily: FB.font, fontSize: 32, fontWeight: 700, letterSpacing: -0.8,
          fontVariantNumeric: 'tabular-nums', lineHeight: 1,
        }}>{value}</span>
        {unit && <span style={{ fontSize: 15, fontWeight: 500, color: FB.muted }}>{unit}</span>}
      </div>
      {delta && (
        <div style={{ marginTop: 6, fontSize: 13, fontWeight: 600, color: deltaColor, letterSpacing: -0.1 }}>
          {delta}
        </div>
      )}
    </div>
  );
}

// ─── Bar chart ─────────────────────────────────────────────────────────
function FBBar({ label, pct, color = FB.accent, value }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '7px 0' }}>
      <div style={{ width: 64, fontSize: 13, color: FB.ink2, fontWeight: 500 }}>{label}</div>
      <div style={{ flex: 1, height: 8, background: FB.cardSubtle, borderRadius: 999, overflow: 'hidden' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: color, borderRadius: 999 }} />
      </div>
      <div style={{ width: 38, fontSize: 12, color: FB.muted, textAlign: 'right',
        fontVariantNumeric: 'tabular-nums' }}>{value}</div>
    </div>
  );
}

// ─── Misc atoms ────────────────────────────────────────────────────────
function FBSpinner({ size = 28, color = FB.ink }) {
  return (
    <div style={{
      width: size, height: size,
      border: `${Math.max(2, size/14)}px solid ${FB.border}`,
      borderTopColor: color, borderRadius: '50%',
      animation: 'fbspin 0.9s linear infinite',
    }} />
  );
}

function FBLockIcon({ size = 14, color = FB.muted }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" style={{ flexShrink: 0 }}>
      <rect x="2.5" y="7" width="11" height="7.5" rx="2" stroke={color} strokeWidth="1.5"/>
      <path d="M5 7V5a3 3 0 016 0v2" stroke={color} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  );
}

function FBChevron({ color = FB.ter }) {
  return (
    <svg width="8" height="14" viewBox="0 0 8 14">
      <path d="M1 1l6 6-6 6" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

// Inject spinner keyframes once
if (typeof document !== 'undefined' && !document.getElementById('fb-anim')) {
  const s = document.createElement('style');
  s.id = 'fb-anim';
  s.textContent = `
    @keyframes fbspin { to { transform: rotate(360deg); } }
    @keyframes fbblink { 0%,49% { opacity: 1; } 50%,100% { opacity: 0; } }
    @keyframes fbfade { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: none; } }
    .fb-cursor { display: inline-block; width: 2px; height: 1.05em; background: ${FB.accent};
      vertical-align: text-bottom; animation: fbblink 1.1s steps(1) infinite; margin-left: 1px; }
    .fb-fade { animation: fbfade 240ms ease-out both; }
  `;
  document.head.appendChild(s);
}

Object.assign(window, {
  FB, FB_DARK, FBScreen, FBNav, FBButton, FBCard, FBLabel, FBStat, FBBar,
  FBSpinner, FBLockIcon, FBChevron,
});
