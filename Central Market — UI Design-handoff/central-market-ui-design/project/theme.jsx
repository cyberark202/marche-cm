/*
 * Marché CM — Design Tokens, Logo, Icons & Atoms
 * Cameroonian palette: forest green (commerce/flag) + sunburst amber + selective coral
 * Built against UI/UX Pro Max rules: vector-only icons, ≥48dp touch targets,
 * semantic tokens, motion 150-300ms, WCAG AA contrast.
 */

// ─────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────
const T = {
  // Brand / Cameroon-inspired palette
  primary:        '#0F7A4F',  // forest green — commerce, growth, flag-green derived
  primaryDark:    '#0A5A3A',
  primaryDeep:    '#063D27',
  primarySoft:    '#E6F2EC',
  primaryTint:    '#F2F9F5',

  accent:         '#F5B400',  // sunburst yellow — flag yellow, CTA
  accentDark:     '#C68F00',
  accentSoft:     '#FEF4D6',

  coral:          '#E5484D',  // flag red — destructive / promo only
  coralSoft:      '#FEECEC',

  // Neutrals (warm, cream-leaning for African daylight)
  bg:             '#FAF7F0',
  surface:        '#FFFFFF',
  surface2:       '#F1ECDE',
  surface3:       '#E8E2D2',

  ink:            '#0E1F18',
  ink2:           '#2D3D36',
  ink3:           '#5C6B64',
  ink4:           '#8F9C96',

  line:           '#E5DECC',
  line2:          '#EDE7D6',

  // Semantic
  success:        '#16A34A',
  warning:        '#D97706',
  info:           '#2563EB',
  danger:         '#DC2626',

  // Shadows (warm, soft)
  shadowSm:       '0 1px 2px rgba(14,31,24,.06), 0 1px 1px rgba(14,31,24,.04)',
  shadowMd:       '0 4px 12px -2px rgba(14,31,24,.08), 0 2px 6px -1px rgba(14,31,24,.04)',
  shadowLg:       '0 12px 28px -8px rgba(14,31,24,.14), 0 4px 12px -2px rgba(14,31,24,.06)',
  shadowBrand:    '0 8px 22px -6px rgba(15,122,79,.45)',
  shadowAccent:   '0 8px 22px -6px rgba(245,180,0,.45)',

  // Radii
  rSm: 8, r: 12, rLg: 18, rXl: 24, rFull: 999,

  // Spacing scale (4dp grid)
  s1: 4, s2: 8, s3: 12, s4: 16, s5: 20, s6: 24, s7: 32, s8: 40, s9: 48,

  // Type
  fontDisplay: "'Plus Jakarta Sans', 'Inter', system-ui, sans-serif",
  fontBody:    "'Plus Jakarta Sans', 'Inter', system-ui, sans-serif",
  fontMono:    "'JetBrains Mono', 'SF Mono', monospace",

  // Motion (UI UX Pro Max guideline: 150-300ms)
  ease:        'cubic-bezier(.4,0,.2,1)',
  easeOut:     'cubic-bezier(0,0,.2,1)',
  duration:    '180ms',
  durationMd:  '240ms',
};

// ─────────────────────────────────────────────────────────────
// Logo — Mont Cameroun "M" + flag star
// The M-shape is formed by two mountain peaks (volcanic ridge).
// A 5-point star (Cameroon flag) sits at the apex.
// ─────────────────────────────────────────────────────────────
function Logo({ size = 44, withWordmark = false, mono = false, light = false }) {
  const id = 'lg' + Math.random().toString(36).slice(2, 7);
  const bg = mono ? '#0E1F18' : T.primary;
  const bg2 = mono ? '#000' : T.primaryDeep;
  const peak = mono ? '#fff' : '#FFFFFF';
  const star = mono ? '#fff' : T.accent;
  const sun = mono ? 'rgba(255,255,255,.18)' : 'rgba(245,180,0,.22)';

  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: size * 0.24 }}>
      <svg width={size} height={size} viewBox="0 0 48 48" style={{ display: 'block', flexShrink: 0 }}>
        <defs>
          <linearGradient id={id + 'bg'} x1="0" y1="0" x2="0" y2="48" gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor={bg}/>
            <stop offset="1" stopColor={bg2}/>
          </linearGradient>
          <linearGradient id={id + 'peak'} x1="0" y1="14" x2="0" y2="42" gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor={peak} stopOpacity="1"/>
            <stop offset="1" stopColor={peak} stopOpacity=".88"/>
          </linearGradient>
        </defs>

        {/* Shield/rounded-square background */}
        <rect x="0" y="0" width="48" height="48" rx="13" fill={`url(#${id}bg)`}/>

        {/* Subtle sunrise halo behind the mountain */}
        <circle cx="24" cy="34" r="16" fill={sun}/>

        {/* Mountains forming the letter M (Mont Cameroun + secondary peak) */}
        {/* Outer M silhouette */}
        <path
          d="M5 40 L5 23 L14 14 L24 26 L34 14 L43 23 L43 40 Z"
          fill={`url(#${id}peak)`}
        />
        {/* Inner valley shadow for depth */}
        <path
          d="M14 14 L24 26 L34 14 L29 18.5 L24 23 L19 18.5 Z"
          fill={bg2}
          opacity="0.22"
        />
        {/* Snow caps */}
        <path d="M11 18 L14 14 L17 17.5 L15 19 L13 18 Z" fill={peak} opacity="0.6"/>
        <path d="M31 17.5 L34 14 L37 18 L35 18 L33 19 Z" fill={peak} opacity="0.6"/>

        {/* Cameroon flag star (5-point) above the peaks */}
        <path
          d="M24 4 L25.6 8.0 L29.9 8.4 L26.6 11.2 L27.5 15.4 L24 13.1 L20.5 15.4 L21.4 11.2 L18.1 8.4 L22.4 8.0 Z"
          fill={star}
          stroke={mono ? '#fff' : T.accentDark}
          strokeWidth="0.4"
          strokeLinejoin="round"
        />
      </svg>

      {withWordmark && (
        <div style={{ lineHeight: 1, display: 'flex', flexDirection: 'column', gap: size * 0.04 }}>
          <div style={{
            fontFamily: T.fontDisplay,
            fontWeight: 800,
            fontSize: size * 0.52,
            letterSpacing: '-0.02em',
            color: light ? '#fff' : T.ink,
          }}>Marché<span style={{color: T.accent}}>.</span></div>
          <div style={{
            fontFamily: T.fontDisplay,
            fontWeight: 700,
            fontSize: size * 0.22,
            letterSpacing: '0.18em',
            color: light ? 'rgba(255,255,255,.7)' : T.primary,
            textTransform: 'uppercase',
          }}>Central Market</div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Icon — single component, lookup by name. 24px viewBox, 2px stroke.
// ─────────────────────────────────────────────────────────────
const ICON_PATHS = {
  // navigation
  home:        <><path d="M3 12L12 3l9 9"/><path d="M5 10v10a1 1 0 0 0 1 1h3v-6h6v6h3a1 1 0 0 0 1-1V10"/></>,
  search:      <><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></>,
  wallet:      <><path d="M3 7v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2H5a2 2 0 0 1-2-2 2 2 0 0 1 2-2h14v4"/><circle cx="17" cy="13" r="1.2" fill="currentColor"/></>,
  bag:         <><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></>,
  package:     <><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></>,
  chat:        <><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></>,
  user:        <><circle cx="12" cy="7" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></>,
  bell:        <><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></>,
  menu:        <><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></>,

  // arrows
  arrowLeft:   <><line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/></>,
  arrowRight:  <><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></>,
  chevronR:    <polyline points="9 18 15 12 9 6"/>,
  chevronD:    <polyline points="6 9 12 15 18 9"/>,
  chevronUp:   <polyline points="18 15 12 9 6 15"/>,

  // actions
  plus:        <><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></>,
  minus:       <line x1="5" y1="12" x2="19" y2="12"/>,
  x:           <><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></>,
  check:       <polyline points="20 6 9 17 4 12"/>,
  checkCircle: <><circle cx="12" cy="12" r="10"/><polyline points="9 12 12 15 16 9"/></>,
  filter:      <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>,
  sort:        <><line x1="3" y1="6" x2="21" y2="6"/><line x1="6" y1="12" x2="18" y2="12"/><line x1="10" y1="18" x2="14" y2="18"/></>,
  heart:       <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>,
  star:        <polygon points="12,2 15,8.5 22,9.3 17,14 18.2,21 12,17.7 5.8,21 7,14 2,9.3 9,8.5"/>,
  share:       <><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></>,
  more:        <><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></>,
  moreV:       <><circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/></>,

  // logistics / commerce
  truck:       <><rect x="1" y="3" width="15" height="13" rx="1"/><path d="M16 8h4l3 3v5h-7"/><circle cx="6" cy="18.5" r="2.5"/><circle cx="18" cy="18.5" r="2.5"/></>,
  shield:      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>,
  shieldCheck: <><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/></>,
  mapPin:      <><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></>,
  calendar:    <><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></>,
  clock:       <><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></>,
  refresh:     <><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></>,

  // input / state
  eye:         <><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></>,
  eyeOff:      <><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></>,
  lock:        <><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></>,
  mail:        <><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></>,
  phone:       <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/>,
  send:        <><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></>,
  smile:       <><circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/></>,
  paperclip:   <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/>,
  mic:         <><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></>,
  camera:      <><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></>,

  // misc
  google:      <path d="M21.35 11.1H12v3.8h5.35a4.6 4.6 0 0 1-2 3.04v2.5h3.23c1.9-1.74 3-4.3 3-7.34 0-.66-.06-1.3-.17-1.92zM12 22c2.7 0 4.96-.9 6.62-2.43l-3.23-2.5c-.9.6-2.05.96-3.39.96-2.6 0-4.8-1.76-5.6-4.13H3.07v2.6A10 10 0 0 0 12 22zm-5.6-9.55c-.2-.6-.32-1.25-.32-1.95s.11-1.35.32-1.95V5.95H3.07a10 10 0 0 0 0 9.1l3.33-2.6zM12 5.8c1.47 0 2.78.5 3.82 1.5l2.86-2.86A10 10 0 0 0 12 2 10 10 0 0 0 3.07 5.95l3.33 2.6C7.2 6.16 9.4 5.8 12 5.8z" fill="currentColor" stroke="none"/>,
  apple:       <path d="M16.4 12.5c0-2.5 2-3.7 2.1-3.8-1.2-1.7-3-2-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.3.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.5 0 2 .8 3.3.8 1.4 0 2.3-1.3 3.2-2.5 1-1.4 1.4-2.8 1.5-2.9-.1 0-2.9-1.1-2.9-4.3zm-2.4-7.8c.7-.8 1.1-2 1-3.2-1 .1-2.2.7-2.9 1.5-.6.7-1.2 1.9-1.1 3 1.1.1 2.3-.5 3-1.3z" fill="currentColor" stroke="none"/>,
  mountain:    <path d="M4 20l5-9 4 6 3-4 4 7z"/>,
  trending:    <><polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/></>,
  trophy:      <><path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4z"/><path d="M7 4H4v3a3 3 0 0 0 3 3M17 4h3v3a3 3 0 0 1-3 3"/></>,
  tag:         <><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></>,
  flame:       <path d="M12 2C8 6 8 10 12 14c4-4 4-8 0-12zM6 14c0 4 3 8 6 8s6-4 6-8c-2 2-4 2-6 0-2 2-4 2-6 0z"/>,
  globe:       <><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></>,
  qr:          <><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM18 18h3v3h-3z"/></>,
  trash:       <><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></>,
  edit:        <><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></>,
  flag:        <><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></>,
  grid:        <><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></>,
  list:        <><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></>,
  scale:       <><path d="M16 16c0-2.21-1.79-4-4-4s-4 1.79-4 4M12 12V4M5 4h14"/><path d="M3 9l5-5 5 5M16 9l-3-5h7l-3 5z"/></>,
};

function Icon({ name, size = 22, color = 'currentColor', strokeWidth = 2, style }) {
  const path = ICON_PATHS[name];
  if (!path) return null;
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24"
      fill="none" stroke={color} strokeWidth={strokeWidth}
      strokeLinecap="round" strokeLinejoin="round"
      style={{ display: 'block', flexShrink: 0, ...style }}
    >
      {path}
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Atoms
// ─────────────────────────────────────────────────────────────
function Btn({ children, variant = 'primary', size = 'md', icon, iconRight, onClick, full, style }) {
  const base = {
    border: 'none', cursor: 'pointer', fontFamily: T.fontDisplay, fontWeight: 700,
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
    transition: `transform ${T.duration} ${T.ease}, background ${T.duration} ${T.ease}, box-shadow ${T.duration} ${T.ease}`,
    width: full ? '100%' : undefined,
    minHeight: 48,  // UI/UX Pro Max touch target
    whiteSpace: 'nowrap',
  };
  const sizes = {
    sm: { padding: '8px 14px', fontSize: 13, borderRadius: 10, minHeight: 40 },
    md: { padding: '12px 18px', fontSize: 14.5, borderRadius: 12, minHeight: 48 },
    lg: { padding: '15px 22px', fontSize: 16, borderRadius: 14, minHeight: 54 },
  };
  const variants = {
    primary: { background: T.primary, color: '#fff', boxShadow: T.shadowBrand },
    accent:  { background: T.accent, color: '#1a0f00', boxShadow: T.shadowAccent },
    dark:    { background: T.ink, color: '#fff' },
    outline: { background: T.surface, color: T.ink, border: `1.5px solid ${T.line}` },
    ghost:   { background: 'transparent', color: T.ink },
    ghostLight:{ background: 'rgba(255,255,255,.12)', color: '#fff', border: '1px solid rgba(255,255,255,.2)' },
    danger:  { background: T.danger, color: '#fff' },
  };
  return (
    <button
      onClick={onClick}
      onMouseDown={e => e.currentTarget.style.transform = 'scale(.97)'}
      onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
      onMouseLeave={e => e.currentTarget.style.transform = 'scale(1)'}
      style={{ ...base, ...sizes[size], ...variants[variant], ...style }}
    >
      {icon && <Icon name={icon} size={size === 'lg' ? 20 : 18}/>}
      {children}
      {iconRight && <Icon name={iconRight} size={size === 'lg' ? 20 : 18}/>}
    </button>
  );
}

function IconBtn({ name, onClick, light, size = 40, badge, style }) {
  return (
    <button
      onClick={onClick}
      onMouseDown={e => e.currentTarget.style.transform = 'scale(.92)'}
      onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
      onMouseLeave={e => e.currentTarget.style.transform = 'scale(1)'}
      style={{
        width: size, height: size, borderRadius: 12, border: 'none',
        background: light ? 'rgba(255,255,255,.15)' : T.surface,
        color: light ? '#fff' : T.ink2,
        display: 'grid', placeItems: 'center', cursor: 'pointer', position: 'relative',
        transition: `transform ${T.duration} ${T.ease}, background ${T.duration} ${T.ease}`,
        ...style,
      }}
    >
      <Icon name={name} size={20}/>
      {badge != null && (
        <span style={{
          position: 'absolute', top: -4, right: -4,
          minWidth: 18, height: 18, padding: '0 5px',
          background: T.coral, color: '#fff', borderRadius: 9,
          fontSize: 10, fontWeight: 800, display: 'grid', placeItems: 'center',
          border: `2px solid ${light ? T.primary : T.surface}`,
          fontFeatureSettings: '"tnum"',
        }}>{badge}</span>
      )}
    </button>
  );
}

function Pill({ children, variant = 'neutral', size = 'md' }) {
  const palettes = {
    neutral: { bg: T.surface2, fg: T.ink2 },
    success: { bg: T.primarySoft, fg: T.primaryDark },
    warn:    { bg: T.accentSoft, fg: '#8E5A00' },
    danger:  { bg: T.coralSoft, fg: T.coral },
    info:    { bg: '#E0E7FF', fg: '#3730A3' },
    dark:    { bg: T.ink, fg: '#fff' },
    accent:  { bg: T.accent, fg: '#1a0f00' },
  };
  const p = palettes[variant] || palettes.neutral;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: size === 'sm' ? '2px 8px' : '4px 10px',
      background: p.bg, color: p.fg,
      borderRadius: 999, fontSize: size === 'sm' ? 10.5 : 11,
      fontWeight: 700, letterSpacing: '.02em',
      lineHeight: 1.3,
    }}>{children}</span>
  );
}

function Avatar({ name = 'A', size = 36, variant = 'primary', light, style }) {
  const initials = name.split(' ').slice(0, 2).map(s => s[0]).join('').toUpperCase();
  const bgs = {
    primary: `linear-gradient(135deg, #1A9670, ${T.primary})`,
    accent: `linear-gradient(135deg, #FFC940, ${T.accentDark})`,
    coral:  `linear-gradient(135deg, #F26B6F, ${T.coral})`,
    info:   `linear-gradient(135deg, #6B8FFF, #2563EB)`,
    dark:   `linear-gradient(135deg, #4A5A54, ${T.ink})`,
  };
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: bgs[variant] || bgs.primary,
      color: variant === 'accent' ? '#1a0f00' : '#fff',
      display: 'grid', placeItems: 'center',
      fontWeight: 700, fontSize: size * 0.36,
      flexShrink: 0,
      boxShadow: light ? '0 0 0 2px rgba(255,255,255,.4)' : undefined,
      ...style,
    }}>{initials}</div>
  );
}

// Image placeholder (no real assets) — soft gradient + watermark icon
function Ph({ icon = 'package', height = 120, radius = 12, tone = 'primary', label }) {
  const tones = {
    primary: { bg: `linear-gradient(135deg, #E6F2EC 0%, #D9EADF 100%)`, fg: T.primary },
    accent:  { bg: `linear-gradient(135deg, #FEF4D6 0%, #FCE9B0 100%)`, fg: T.accentDark },
    cream:   { bg: `linear-gradient(135deg, #F5F0E0 0%, #EDE5CC 100%)`, fg: T.ink3 },
    coral:   { bg: `linear-gradient(135deg, #FEECEC 0%, #FBD9DA 100%)`, fg: T.coral },
    sky:     { bg: `linear-gradient(135deg, #E0EAFF 0%, #C7D6FB 100%)`, fg: '#3730A3' },
  };
  const t = tones[tone] || tones.primary;
  return (
    <div style={{
      height, borderRadius: radius, background: t.bg,
      display: 'grid', placeItems: 'center', color: t.fg, position: 'relative', overflow: 'hidden',
    }}>
      <Icon name={icon} size={Math.min(48, height * 0.4)} strokeWidth={1.3}/>
      {label && <div style={{
        position: 'absolute', bottom: 8, left: 10, right: 10,
        fontSize: 10, fontWeight: 700, opacity: .55, textTransform: 'uppercase', letterSpacing: '0.08em',
      }}>{label}</div>}
    </div>
  );
}

// Stars rating
function Stars({ value = 4.5, size = 12 }) {
  return (
    <span style={{ display: 'inline-flex', gap: 1, color: T.accent }}>
      {[1,2,3,4,5].map(i => (
        <Icon key={i} name="star" size={size} color={i <= Math.round(value) ? T.accent : T.surface3}/>
      ))}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────
// Brand status bar (replaces android starter when needed)
// ─────────────────────────────────────────────────────────────
function StatusBar({ dark = false, bg }) {
  const c = dark ? '#fff' : T.ink;
  return (
    <div style={{
      height: 36, display: 'flex', alignItems: 'center',
      justifyContent: 'space-between', padding: '0 18px',
      position: 'relative', background: bg || 'transparent',
      fontFamily: T.fontDisplay, flexShrink: 0,
    }}>
      <span style={{ fontSize: 13, fontWeight: 600, color: c, letterSpacing: '.02em' }}>9:30</span>
      <div style={{
        position: 'absolute', left: '50%', top: 8, transform: 'translateX(-50%)',
        width: 22, height: 22, borderRadius: 100, background: '#1a1a1a',
      }}/>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: c }}>
        {/* signal */}
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M2 22h2v-4H2v4zm4 0h2v-8H6v8zm4 0h2v-12h-2v12zm4 0h2V6h-2v16zm4 0h2V2h-2v20z"/></svg>
        {/* wifi */}
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 18l3-3a4 4 0 0 0-6 0l3 3zm0-6l5.5-5.5a8 8 0 0 0-11 0L12 12zm0-6L20 0a12 12 0 0 0-16 0l8 8z" transform="translate(0 6)"/></svg>
        {/* battery */}
        <svg width="22" height="14" viewBox="0 0 24 14" fill="currentColor"><rect x="1" y="2" width="19" height="10" rx="2" fill="none" stroke="currentColor" strokeWidth="1.2"/><rect x="3" y="4" width="13" height="6" rx="0.5"/><rect x="20.5" y="5" width="1.5" height="4" rx="0.5"/></svg>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Bottom nav (custom branded)
// ─────────────────────────────────────────────────────────────
function BottomNav({ active, onNavigate }) {
  const items = [
    { id: 'home',    icon: 'home',    label: 'Accueil' },
    { id: 'catalog', icon: 'grid',    label: 'Catalogue' },
    { id: 'wallet',  icon: 'wallet',  label: 'Wallet' },
    { id: 'orders',  icon: 'package', label: 'Commandes', badge: 2 },
    { id: 'profile', icon: 'user',    label: 'Profil' },
  ];
  return (
    <div style={{
      background: T.surface,
      borderTop: `1px solid ${T.line2}`,
      padding: '6px 4px 8px',
      display: 'grid', gridTemplateColumns: 'repeat(5,1fr)',
      flexShrink: 0,
    }}>
      {items.map(it => {
        const isActive = active === it.id;
        return (
          <button key={it.id} onClick={() => onNavigate?.(it.id)} style={{
            background: 'none', border: 'none', cursor: 'pointer',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            padding: '8px 4px', borderRadius: 10, position: 'relative',
            color: isActive ? T.primary : T.ink3,
            minHeight: 56,
            transition: `color ${T.duration} ${T.ease}`,
          }}>
            <div style={{
              padding: '4px 14px',
              background: isActive ? T.primarySoft : 'transparent',
              borderRadius: 999,
              transition: `background ${T.duration} ${T.ease}`,
              position: 'relative',
            }}>
              <Icon name={it.icon} size={22} color={isActive ? T.primary : T.ink3} strokeWidth={isActive ? 2.4 : 2}/>
              {it.badge && (
                <span style={{
                  position: 'absolute', top: 2, right: 6,
                  minWidth: 16, height: 16, padding: '0 4px',
                  background: T.coral, color: '#fff', borderRadius: 8,
                  fontSize: 9.5, fontWeight: 800, display: 'grid', placeItems: 'center',
                  border: `2px solid ${T.surface}`,
                }}>{it.badge}</span>
              )}
            </div>
            <span style={{
              fontSize: 10.5, fontWeight: 600,
              letterSpacing: '.01em',
              fontFamily: T.fontDisplay,
              color: isActive ? T.primary : T.ink3,
            }}>{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen header (branded top bar with back button or logo)
// ─────────────────────────────────────────────────────────────
function ScreenHeader({ title, subtitle, onBack, right, dark, transparent, center }) {
  return (
    <div style={{
      padding: '8px 16px 10px',
      display: 'flex', alignItems: 'center', gap: 12,
      background: transparent ? 'transparent' : (dark ? 'transparent' : T.bg),
      flexShrink: 0,
      minHeight: 56,
    }}>
      {onBack && (
        <IconBtn name="arrowLeft" onClick={onBack} light={dark} style={{
          background: dark ? 'rgba(255,255,255,.12)' : T.surface,
          border: dark ? '1px solid rgba(255,255,255,.18)' : `1px solid ${T.line}`,
        }}/>
      )}
      <div style={{ flex: 1, minWidth: 0, textAlign: center ? 'center' : 'left' }}>
        {title && <div style={{
          fontFamily: T.fontDisplay, fontWeight: 700, fontSize: 17,
          letterSpacing: '-0.01em',
          color: dark ? '#fff' : T.ink,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{title}</div>}
        {subtitle && <div style={{
          fontSize: 12, color: dark ? 'rgba(255,255,255,.7)' : T.ink3,
          marginTop: 2, fontWeight: 500,
        }}>{subtitle}</div>}
      </div>
      {right}
    </div>
  );
}

// expose
Object.assign(window, {
  T, Logo, Icon, Btn, IconBtn, Pill, Avatar, Ph, Stars,
  StatusBar, BottomNav, ScreenHeader,
});
