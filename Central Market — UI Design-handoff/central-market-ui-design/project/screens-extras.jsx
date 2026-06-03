/*
 * Marché CM — Extras: Notifications inbox + Logo lab + Dispute multi-view
 */

// ─────────────────────────────────────────────────────────────
// NOTIFICATIONS — multi-domain inbox
// ─────────────────────────────────────────────────────────────
function NotificationsScreen({ nav }) {
  const [tab, setTab] = React.useState('Tout');
  const notifs = [
    { domain: 'kyc', ic: 'shieldCheck', t: 'KYC validé !', s: 'Votre dossier a été approuvé. Bienvenue sur Marché CM.', time: '2 min', tone: 'success', unread: true, action: () => nav('home') },
    { domain: 'orders', ic: 'truck', t: 'Colis en route', s: 'Express Logistics est à Edéa · ETA 18 mai 14:30', time: '12 min', tone: 'warn', unread: true, action: () => nav('tracking') },
    { domain: 'chat', ic: 'chat', t: 'Tropical Foods', s: 'Le devis transitaire est prêt, vous validez ?', time: '38 min', tone: 'info', unread: true, action: () => nav('chat-thread') },
    { domain: 'wallet', ic: 'wallet', t: 'Recharge réussie', s: '+ 500 000 FCFA via MTN Mobile Money', time: '2 h', tone: 'success' },
    { domain: 'orders', ic: 'package', t: 'Commande acceptée', s: 'CMD #84F2 · Tropical Foods a confirmé', time: 'hier', tone: 'success' },
    { domain: 'dispute', ic: 'flag', t: 'Litige résolu', s: 'CMD #62B1F0 · remboursement 1,4 M F crédité', time: '3 j', tone: 'coral' },
    { domain: 'promo', ic: 'tag', t: 'Promo riz 50 kg', s: '−15 % chez Yaoundé Foods jusqu\'au 30 mai', time: '4 j', tone: 'warn' },
    { domain: 'wallet', ic: 'shield', t: 'Séquestre libéré', s: 'CMD #71A09C · 580 000 F → votre wallet', time: '5 j', tone: 'success' },
  ];
  const filtered = tab === 'Tout' ? notifs : notifs.filter(n => n.domain === tab.toLowerCase());

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('home')} title="Notifications" subtitle="3 non lues" right={<IconBtn name="moreV"/>}/>

      <div style={{ display: 'flex', gap: 6, padding: '0 16px 10px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['Tout', 'Orders', 'Wallet', 'Chat', 'KYC', 'Dispute', 'Promo'].map(c => (
          <button key={c} onClick={() => setTab(c)} style={{
            flexShrink: 0, padding: '7px 12px', borderRadius: 999,
            background: tab === c ? T.ink : T.surface,
            color: tab === c ? '#fff' : T.ink2,
            border: `1px solid ${tab === c ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 700, cursor: 'pointer', whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', background: T.surface }}>
        {filtered.map((n, i, arr) => (
          <button key={i} onClick={n.action} style={{
            width: '100%', display: 'flex', gap: 12, padding: '14px 16px',
            border: 'none', background: n.unread ? T.primarySoft : 'transparent',
            borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            cursor: 'pointer', textAlign: 'left', alignItems: 'center', position: 'relative',
          }}>
            {n.unread && <span style={{
              position: 'absolute', left: 6, top: '50%', transform: 'translateY(-50%)',
              width: 6, height: 6, borderRadius: '50%', background: T.primary,
            }}/>}
            <div style={{
              width: 42, height: 42, borderRadius: 12, display: 'grid', placeItems: 'center', flexShrink: 0,
              background: n.tone === 'success' ? T.primarySoft :
                          n.tone === 'warn' ? T.accentSoft :
                          n.tone === 'info' ? '#E0E7FF' : T.coralSoft,
              color: n.tone === 'success' ? T.primaryDark :
                     n.tone === 'warn' ? '#8E5A00' :
                     n.tone === 'info' ? '#3730A3' : T.coral,
            }}><Icon name={n.ic} size={18}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 6 }}>
                <span style={{ fontSize: 13.5, fontWeight: 700, color: T.ink }}>{n.t}</span>
                <span style={{ fontSize: 10.5, color: T.ink3, fontWeight: 600, flexShrink: 0 }}>{n.time}</span>
              </div>
              <div style={{ fontSize: 12, color: T.ink2, marginTop: 2, lineHeight: 1.4 }}>{n.s}</div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// LOGO LAB — 4 variants
// ─────────────────────────────────────────────────────────────
function MonogramVariant({ size = 88 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48">
      <rect x="0" y="0" width="48" height="48" rx="13" fill={T.primary}/>
      <text x="24" y="32" textAnchor="middle" fontSize="22" fontWeight="800" fill="#fff" fontFamily="'Plus Jakarta Sans'" letterSpacing="-0.04em">
        M<tspan fill={T.accent}>·</tspan>CM
      </text>
      <text x="24" y="42" textAnchor="middle" fontSize="4.5" fontWeight="700" fill="#fff" fontFamily="'Plus Jakarta Sans'" opacity="0.5" letterSpacing="0.2em">MARKET</text>
    </svg>
  );
}

function SunFurrowVariant({ size = 88 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48">
      <rect x="0" y="0" width="48" height="48" rx="13" fill={T.primaryDeep}/>
      <circle cx="24" cy="20" r="8" fill={T.accent}/>
      {[0, 45, 90, 135, 180, 225, 270, 315].map(deg => (
        <rect key={deg} x="23" y="6" width="2" height="3.5" fill={T.accent} rx="1"
          transform={`rotate(${deg} 24 20)`}/>
      ))}
      <path d="M 4 36 Q 24 30 44 36" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" opacity="0.95"/>
      <path d="M 2 41 Q 24 35 46 41" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" opacity="0.7"/>
      <path d="M 0 46 Q 24 40 48 46" fill="none" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" opacity="0.45"/>
    </svg>
  );
}

function BoldStarVariant({ size = 88 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48">
      <rect x="0" y="0" width="48" height="48" rx="13" fill={T.accent}/>
      <circle cx="24" cy="24" r="20" fill="none" stroke={T.primaryDeep} strokeWidth="1.5" opacity=".15"/>
      <path d="M24 6 L29 18.7 L43 19.8 L32.5 28.7 L35.7 42.3 L24 35 L12.3 42.3 L15.5 28.7 L5 19.8 L19 18.7 Z"
        fill={T.primaryDeep}/>
    </svg>
  );
}

function LogoLabScreen({ nav }) {
  const variants = [
    {
      name: 'Mont + Étoile',
      sub: 'Direction actuelle · paysage + flag',
      desc: 'Le M des deux pics du Mont Cameroun, étoile à 5 pointes du drapeau. Lisible, ancré, racines naturelles.',
      logo: <Logo size={88}/>,
      current: true,
    },
    {
      name: 'Monogramme M·CM',
      sub: 'Lettré · épuré · type-driven',
      desc: 'Monogramme typographique pur. Idéal pour usages réduits (favicon, app icon, watermark).',
      logo: <MonogramVariant size={88}/>,
    },
    {
      name: 'Soleil & sillons',
      sub: 'Métaphore agricole · marché vivrier',
      desc: 'Soleil radiant sur les sillons d\'un champ. Évoque le commerce vivrier et la générosité.',
      logo: <SunFurrowVariant size={88}/>,
    },
    {
      name: 'Étoile pleine',
      sub: 'Symbole national · audacieux',
      desc: 'L\'étoile à 5 pointes seule, en plein. Direction marque la plus politique et "patrimoine".',
      logo: <BoldStarVariant size={88}/>,
    },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('home')} title="Variantes de logo" subtitle="4 directions à comparer"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px 16px' }}>
        {variants.map((v, i) => (
          <div key={i} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 18,
            padding: 16, marginBottom: 12,
            boxShadow: v.current ? `0 0 0 2px ${T.primary}, 0 0 0 5px ${T.primarySoft}` : T.shadowSm,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 12 }}>
              <div style={{
                width: 108, height: 108, borderRadius: 16, background: T.bg,
                display: 'grid', placeItems: 'center', flexShrink: 0,
                border: `1px solid ${T.line2}`,
              }}>{v.logo}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ fontSize: 14.5, fontWeight: 800 }}>{v.name}</span>
                  {v.current && <Pill variant="success" size="sm">ACTUEL</Pill>}
                </div>
                <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 3, fontWeight: 600 }}>{v.sub}</div>
              </div>
            </div>
            <div style={{ fontSize: 12, color: T.ink2, lineHeight: 1.5 }}>{v.desc}</div>

            <div style={{ display: 'flex', gap: 6, marginTop: 12 }}>
              <Btn variant="outline" size="sm" style={{ flex: 1 }}>Décliner</Btn>
              <Btn variant={v.current ? 'dark' : 'primary'} size="sm" style={{ flex: 1 }} icon={v.current ? null : 'check'}>
                {v.current ? 'Actuel' : 'Choisir'}
              </Btn>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// DISPUTE MULTI-VIEW HUB
// ─────────────────────────────────────────────────────────────
function DisputeHubScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('home')} title="Litige #62B1F0" subtitle="Visualiser depuis chaque rôle"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px 16px' }}>
        <div style={{
          background: `linear-gradient(135deg, ${T.coral} 0%, #B91C1C 100%)`,
          color: '#fff', borderRadius: 16, padding: 14, marginBottom: 14, position: 'relative', overflow: 'hidden',
        }}>
          <Icon name="flag" size={100} style={{ position: 'absolute', right: -15, bottom: -15, opacity: .15 }}/>
          <Pill variant="dark" size="sm">SÉQUESTRE GELÉ</Pill>
          <div style={{ fontSize: 13, marginTop: 8, fontWeight: 700 }}>Marchandise endommagée</div>
          <div style={{ fontSize: 11.5, opacity: .85, marginTop: 3 }}>1 800 000 FCFA · ouvert il y a 2 jours</div>
        </div>

        <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>3 perspectives + arbitrage</div>

        {[
          { id: 'dispute-buyer', role: 'Acheteur', name: 'Awa Kamga', sub: 'Plaignante · vue acheteur', icon: 'bag', tone: 'info' },
          { id: 'dispute-vendor', role: 'Vendeur', name: 'Tropical Foods', sub: 'Témoin · vue vendeur', icon: 'package', tone: 'success' },
          { id: 'dispute-livreur', role: 'Livreur', name: 'SOTRAM Cameroun', sub: 'Mis en cause · vue transitaire', icon: 'truck', tone: 'warn' },
          { id: 'dispute-arbitre', role: 'Arbitre', name: 'Conversation tripartite', sub: 'Chat avec admin · 3 parties', icon: 'chat', tone: 'coral' },
        ].map((v, i) => (
          <button key={i} onClick={() => nav(v.id)} style={{
            width: '100%', background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14,
            padding: 14, marginBottom: 10, cursor: 'pointer', textAlign: 'left',
            display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <div style={{
              width: 42, height: 42, borderRadius: 12, display: 'grid', placeItems: 'center',
              background: v.tone === 'info' ? '#E0E7FF' :
                          v.tone === 'success' ? T.primarySoft :
                          v.tone === 'warn' ? T.accentSoft : T.coralSoft,
              color: v.tone === 'info' ? '#3730A3' :
                     v.tone === 'success' ? T.primary :
                     v.tone === 'warn' ? '#8E5A00' : T.coral,
            }}><Icon name={v.icon} size={20}/></div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, color: T.ink3, fontWeight: 700, letterSpacing: '.04em', textTransform: 'uppercase' }}>{v.role}</div>
              <div style={{ fontSize: 14, fontWeight: 700, color: T.ink, marginTop: 1 }}>{v.name}</div>
              <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{v.sub}</div>
            </div>
            <Icon name="chevronR" size={16} color={T.ink3}/>
          </button>
        ))}
      </div>
    </div>
  );
}

// View 1 — Buyer perspective
function DisputeBuyerScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('dispute-hub')} title="Mon litige" subtitle="LIT #62B1F0 · vue Acheteur"/>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        <div style={{ padding: '14px', background: T.coralSoft, borderRadius: 14, color: T.coral, fontSize: 12.5, fontWeight: 600, lineHeight: 1.5 }}>
          Vous avez déclaré que 30 bidons sur 200 étaient percés à la livraison. Notre équipe arbitre.
        </div>

        <div style={{ marginTop: 16, fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Vos preuves jointes (3)</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {['coral', 'coral', 'accent'].map((tone, i) => (
            <div key={i} style={{ aspectRatio: '1 / 1', borderRadius: 10, overflow: 'hidden' }}>
              <Ph icon="camera" height="100%" radius={0} tone={tone} label={`PHOTO ${i+1}`}/>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 16, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: T.ink2 }}>Vous avez demandé :</div>
          <div style={{ fontSize: 22, fontWeight: 800, fontFeatureSettings: '"tnum"', marginTop: 4, color: T.coral }}>Remboursement total</div>
          <div style={{ fontSize: 11, color: T.ink3, marginTop: 4 }}>1 800 000 FCFA séquestrés en attente</div>
        </div>

        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Suivi de la procédure</div>
          {[
            { done: true, t: 'Litige ouvert', s: '18 mai 14:22 · vos preuves uploadées' },
            { done: true, t: 'Vendeur a témoigné', s: '19 mai 09:30' },
            { done: true, t: 'Livreur a répondu', s: '18 mai 16:05 · contestation' },
            { active: true, t: 'Arbitrage admin en cours', s: 'décision sous 24 h' },
            { t: 'Application de la décision', s: 'remboursement ou libération' },
          ].map((s, i) => (
            <div key={i} style={{ display: 'flex', gap: 10, padding: '10px 0', alignItems: 'center' }}>
              <span style={{
                width: 22, height: 22, borderRadius: '50%',
                background: s.done ? T.primary : s.active ? T.accent : T.surface2,
                display: 'grid', placeItems: 'center', color: '#fff',
                animation: s.active ? 'pulse 1.6s ease infinite' : 'none',
              }}>{s.done && <Icon name="check" size={12} color="#fff" strokeWidth={3}/>}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: s.done || s.active ? T.ink : T.ink3 }}>{s.t}</div>
                <div style={{ fontSize: 11, color: T.ink3 }}>{s.s}</div>
              </div>
            </div>
          ))}
        </div>
        <style>{`@keyframes pulse { 0%,100% { box-shadow: 0 0 0 0 rgba(245,180,0,.5);} 50% { box-shadow: 0 0 0 10px rgba(245,180,0,0);} }`}</style>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0, display: 'flex', gap: 8 }}>
        <Btn variant="outline" size="md" style={{ flex: 1 }} icon="chat" onClick={() => nav('dispute-arbitre')}>Discuter</Btn>
        <Btn variant="dark" size="md" style={{ flex: 1 }} icon="plus">Preuve +</Btn>
      </div>
    </div>
  );
}

// View 2 — Vendor (witness)
function DisputeVendorScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('dispute-hub')} title="Témoignage demandé" subtitle="LIT #62B1F0 · vue Vendeur"/>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        <div style={{ padding: '14px', background: T.accentSoft, borderRadius: 14, color: '#8E5A00', fontSize: 12.5, fontWeight: 600, lineHeight: 1.5 }}>
          Awa Kamga a ouvert un litige sur sa commande. Vous n'êtes pas mis en cause mais votre témoignage est utile à l'arbitrage.
        </div>

        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12, display: 'flex', gap: 10, alignItems: 'center' }}>
          <Ph icon="package" height={48} radius={9} tone="accent"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Huile palme 20 L × 200</div>
            <div style={{ fontSize: 11, color: T.ink3, marginTop: 2 }}>CMD #84F2 · livré par SOTRAM</div>
          </div>
          <Pill variant="success" size="sm">Envoyé</Pill>
        </div>

        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Votre déclaration</div>
          <div style={{ fontSize: 13, color: T.ink2, fontStyle: 'italic', lineHeight: 1.5, padding: '10px 12px', background: T.surface2, borderRadius: 10 }}>
            « Confirmation : emballage standard certifié, état neuf au chargement. Photos d'enlèvement jointes. »
          </div>
        </div>

        <div style={{ marginTop: 14, fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Photos d'enlèvement (3)</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {['primary', 'primary', 'cream'].map((tone, i) => (
            <div key={i} style={{ aspectRatio: '1 / 1', borderRadius: 10, overflow: 'hidden' }}>
              <Ph icon="camera" height="100%" radius={0} tone={tone} label={`STOCK ${i+1}`}/>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 14, padding: 12, background: T.primarySoft, borderRadius: 12, fontSize: 11.5, color: T.primaryDark, lineHeight: 1.5 }}>
          <Icon name="shieldCheck" size={14} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 6 }}/>
          Votre réputation et votre paiement ne sont pas affectés : ce litige porte sur le transport, pas sur votre marchandise.
        </div>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="md" full icon="chat" onClick={() => nav('dispute-arbitre')}>Rejoindre la conversation arbitrage</Btn>
      </div>
    </div>
  );
}

// View 3 — Livreur (accused)
function DisputeLivreurScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('dispute-hub')} title="Litige contesté" subtitle="LIT #62B1F0 · vue Livreur"/>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        <div style={{ padding: '14px', background: T.coralSoft, borderRadius: 14, color: T.coral, fontSize: 12.5, fontWeight: 600, lineHeight: 1.5 }}>
          Vous êtes mis en cause par Awa Kamga. Votre paiement de <b>90 000 F</b> est gelé en attendant arbitrage.
        </div>

        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Votre réponse</div>
          <div style={{ fontSize: 13, color: T.ink2, fontStyle: 'italic', lineHeight: 1.5, padding: '10px 12px', background: T.surface2, borderRadius: 10 }}>
            « Bidons étaient OK au chargement. Photos d'enlèvement jointes. Trajet sans incident. »
          </div>
        </div>

        <div style={{ marginTop: 14, fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Vos preuves jointes (4)</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6 }}>
          {['cream', 'cream', 'primary', 'sky'].map((tone, i) => (
            <div key={i} style={{ aspectRatio: '1 / 1', borderRadius: 8, overflow: 'hidden' }}>
              <Ph icon="camera" height="100%" radius={0} tone={tone} label={`P${i+1}`}/>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Issues possibles</div>
          {[
            { l: 'Décision en votre faveur', s: '+ 90 000 F libérés', tone: 'success' },
            { l: 'Partage 50/50', s: '+ 45 000 F libérés', tone: 'warn' },
            { l: 'Décision en faveur acheteur', s: '0 F · 1 strike sur réputation', tone: 'danger' },
          ].map((o, i) => (
            <div key={i} style={{
              padding: '10px 12px', borderRadius: 10, marginBottom: i < 2 ? 6 : 0,
              background: T.surface2, display: 'flex', alignItems: 'center', gap: 10,
            }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%',
                background: o.tone === 'success' ? T.success : o.tone === 'warn' ? T.accent : T.coral }}/>
              <span style={{ fontSize: 12, fontWeight: 700, flex: 1 }}>{o.l}</span>
              <span style={{ fontSize: 11, color: T.ink3, fontFeatureSettings: '"tnum"' }}>{o.s}</span>
            </div>
          ))}
        </div>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0, display: 'flex', gap: 8 }}>
        <Btn variant="outline" size="md" style={{ flex: 1 }} icon="plus">Preuve +</Btn>
        <Btn variant="primary" size="md" style={{ flex: 1 }} icon="chat" onClick={() => nav('dispute-arbitre')}>Conversation</Btn>
      </div>
    </div>
  );
}

// View 4 — Arbitrage tripartite chat
function DisputeArbitreScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <div style={{
        padding: '8px 12px 10px', display: 'flex', alignItems: 'center', gap: 10,
        background: T.surface, borderBottom: `1px solid ${T.line2}`, flexShrink: 0,
      }}>
        <IconBtn name="arrowLeft" onClick={() => nav('dispute-hub')} style={{ background: 'transparent', border: 'none' }}/>
        <div style={{ display: 'flex', marginLeft: 4 }}>
          <Avatar name="Awa Kamga" size={32} variant="info" style={{ marginRight: -10, border: '2px solid #fff' }}/>
          <Avatar name="Tropical Foods" size={32} variant="primary" style={{ marginRight: -10, border: '2px solid #fff' }}/>
          <Avatar name="SOTRAM Cameroun" size={32} variant="dark" style={{ border: '2px solid #fff' }}/>
        </div>
        <div style={{ flex: 1, minWidth: 0, marginLeft: 8 }}>
          <div style={{ fontSize: 13.5, fontWeight: 700 }}>Arbitrage tripartite</div>
          <div style={{ fontSize: 11, color: T.ink3 }}>LIT #62B1F0 · Admin présent</div>
        </div>
        <Pill variant="danger" size="sm">EN ARBITRAGE</Pill>
      </div>

      <div style={{
        flex: 1, overflow: 'auto', padding: '14px', display: 'flex', flexDirection: 'column', gap: 8,
        background: `radial-gradient(60% 80% at 50% 0%, rgba(220,38,38,.04), transparent 60%), ${T.bg}`,
      }}>
        <div style={{ textAlign: 'center', fontSize: 11, color: T.ink3, fontWeight: 600, marginTop: 4 }}>18 mai · ouverture du litige</div>

        <DisputeMsg from="Awa Kamga" tone="info" text="Bonjour, 30 bidons sur 200 sont percés à la réception. J'ai pris des photos."/>
        <DisputeMsg from="SOTRAM Cameroun" tone="warn" text="Désolé pour la situation. Mais les bidons étaient intacts à l'enlèvement, voir mes photos."/>
        <DisputeMsg from="Tropical Foods" tone="primary" text="Emballage certifié neuf au moment du chargement. Je confirme la qualité standard."/>

        <div style={{ alignSelf: 'center', padding: '6px 12px', background: T.coralSoft, color: T.coral, borderRadius: 999, fontSize: 11, fontWeight: 700, marginTop: 6 }}>
          <Icon name="shield" size={11} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }}/>
          Admin Kerian a rejoint la conversation
        </div>

        <DisputeMsg from="Admin Kerian" tone="coral" admin text="J'ai bien reçu les preuves de chaque partie. Avant décision, SOTRAM, pouvez-vous nous indiquer l'état du véhicule pendant le transport ? Pluie, secousses ?"/>
        <DisputeMsg from="SOTRAM Cameroun" tone="warn" text="Pluie modérée entre Edéa et Boumnyebel mais bâche intacte. Pas de choc enregistré."/>
        <DisputeMsg from="Awa Kamga" tone="info" text="J'ajoute : 2 cartons étaient mouillés à l'extérieur. Photo jointe ci-dessous."/>
        <DisputeMsg from="Awa Kamga" tone="info" img="coral"/>
        <DisputeMsg from="Admin Kerian" tone="coral" admin text="Merci à tous. Décision prendre dans les 12 h après examen complet des éléments."/>

        <div style={{ alignSelf: 'center', padding: '6px 12px', background: T.accentSoft, color: '#8E5A00', borderRadius: 999, fontSize: 11, fontWeight: 700, marginTop: 6 }}>
          <Icon name="clock" size={11} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }}/>
          Décision attendue avant 19 mai 22:00
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '8px 10px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
        <IconBtn name="paperclip" style={{ background: 'transparent', border: 'none' }}/>
        <div style={{
          flex: 1, background: T.surface2, borderRadius: 22, padding: '0 14px',
          display: 'flex', alignItems: 'center', gap: 8, minHeight: 44,
        }}>
          <input placeholder="Répondre dans l'arbitrage…" style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 14 }}/>
          <Icon name="camera" size={18} color={T.ink3}/>
        </div>
        <button style={{
          width: 44, height: 44, borderRadius: '50%',
          background: T.primary, color: '#fff', border: 'none', cursor: 'pointer',
          display: 'grid', placeItems: 'center', boxShadow: T.shadowBrand,
        }}>
          <Icon name="send" size={18} strokeWidth={2.4}/>
        </button>
      </div>
    </div>
  );
}

function DisputeMsg({ from, tone, text, img, admin }) {
  const palettes = {
    info: { bg: '#E0E7FF', fg: '#3730A3' },
    primary: { bg: T.primarySoft, fg: T.primary },
    warn: { bg: T.accentSoft, fg: '#8E5A00' },
    coral: { bg: T.coralSoft, fg: T.coral },
  };
  const p = palettes[tone];
  return (
    <div style={{ alignSelf: 'flex-start', maxWidth: '88%', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 4px' }}>
        <Avatar name={from} size={20} variant={tone === 'info' ? 'info' : tone === 'primary' ? 'primary' : tone === 'warn' ? 'dark' : 'coral'}/>
        <span style={{ fontSize: 10.5, fontWeight: 700, color: T.ink2 }}>{from}</span>
        {admin && <Pill variant="danger" size="sm">ADMIN</Pill>}
      </div>
      {text && (
        <div style={{
          background: p.bg, color: p.fg, padding: '9px 13px', borderRadius: 14, borderBottomLeftRadius: 4,
          fontSize: 13, lineHeight: 1.42, fontWeight: 500,
          border: admin ? `1.5px solid ${T.coral}` : 'none',
        }}>{text}</div>
      )}
      {img && (
        <div style={{ width: 140, height: 100, borderRadius: 12, overflow: 'hidden' }}>
          <Ph icon="camera" height="100%" radius={0} tone={img} label="PREUVE"/>
        </div>
      )}
    </div>
  );
}

Object.assign(window, {
  NotificationsScreen,
  MonogramVariant, SunFurrowVariant, BoldStarVariant, LogoLabScreen,
  DisputeHubScreen, DisputeBuyerScreen, DisputeVendorScreen, DisputeLivreurScreen, DisputeArbitreScreen,
  DisputeMsg,
});
