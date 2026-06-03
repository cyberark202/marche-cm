/*
 * Marché CM — Screens part B
 * Wallet, Topup, Orders, Tracking, ChatList, ChatThread, Profile
 */

// ─────────────────────────────────────────────────────────────
// 7) WALLET — Balance + escrow + transactions + methods
// ─────────────────────────────────────────────────────────────
function WalletScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Portefeuille" right={<><IconBtn name="refresh"/><IconBtn name="moreV"/></>}/>

      {/* Wallet card */}
      <div style={{ padding: '0 16px 14px' }}>
        <div style={{
          background: `linear-gradient(140deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          borderRadius: 22, padding: '20px 20px 22px', color: '#fff',
          position: 'relative', overflow: 'hidden',
          boxShadow: T.shadowBrand,
        }}>
          {/* decorative star and circle */}
          <Icon name="star" size={120} color={T.accent} style={{ position: 'absolute', right: -28, top: -28, opacity: .08 }}/>
          <div style={{ position: 'absolute', right: -40, bottom: -40, width: 160, height: 160, borderRadius: '50%', background: 'rgba(245,180,0,.1)' }}/>

          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <span style={{ fontSize: 11, letterSpacing: '.08em', opacity: .8, fontWeight: 700, textTransform: 'uppercase' }}>Solde disponible</span>
            <Pill variant="accent" size="sm">PIN actif</Pill>
          </div>
          <div style={{ fontSize: 34, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 4 }}>
            1 248 500<span style={{ fontSize: 14, opacity: .7, marginLeft: 6, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .8, marginTop: 4, fontFamily: T.fontMono }}>
            ID · CM·8A4F2E1B
          </div>

          <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
            <Btn variant="accent" size="md" icon="plus" onClick={() => nav('topup')} style={{ flex: 1 }}>Recharger</Btn>
            <Btn variant="ghostLight" size="md" icon="arrowRight" style={{ flex: 1 }}>Envoyer</Btn>
            <IconBtn name="qr" light style={{ background: 'rgba(255,255,255,.15)' }}/>
          </div>
        </div>
      </div>

      {/* Quick stats */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px 14px' }}>
        <StatCard ic="shield" label="Séquestre HELD" value="2 900 000" sub="2 commandes" tone="info"/>
        <StatCard ic="trending" label="Mai 2026" value="+ 384 200" sub="vs avril" tone="success"/>
      </div>

      {/* Methods */}
      <Section title="Moyens de recharge">
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px' }}>
          {[
            { logo: 'MTN', color: '#FFCC00', dark: '#1A1A1A', name: 'MTN Mobile Money', sub: 'Instantané · 1 %' },
            { logo: 'OM', color: '#FF6600', dark: '#fff', name: 'Orange Money', sub: 'Instantané · 1 %' },
            { logo: 'VISA', color: '#1A1F71', dark: '#fff', name: 'Carte Visa', sub: '3-D Secure' },
            { logo: 'MC', color: '#EB001B', dark: '#fff', name: 'Mastercard', sub: '3-D Secure' },
          ].map((m, i) => (
            <button key={i} onClick={() => nav('topup')} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12,
              cursor: 'pointer', textAlign: 'left', display: 'flex', flexDirection: 'column', gap: 8,
              transition: `border-color ${T.duration} ${T.ease}, transform ${T.duration} ${T.ease}`,
            }}>
              <div style={{
                width: 44, height: 28, borderRadius: 6, background: m.color, color: m.dark,
                display: 'grid', placeItems: 'center', fontWeight: 800, fontSize: 11, letterSpacing: '.04em',
              }}>{m.logo}</div>
              <div>
                <div style={{ fontSize: 13, fontWeight: 700, color: T.ink }}>{m.name}</div>
                <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 2 }}>{m.sub}</div>
              </div>
            </button>
          ))}
        </div>
      </Section>

      {/* Transactions */}
      <Section title="Transactions récentes" action="Voir tout">
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, margin: '0 16px', overflow: 'hidden' }}>
          {[
            { ic: 'arrowRight', tone: 'success', t: 'Recharge MTN MoMo', s: '+237 6•• •• 482 · 09:42', v: '+ 500 000', st: 'SUCCESS', pos: true },
            { ic: 'shield', tone: 'info', t: 'Séquestre CMD #84F2', s: 'Huile palme · 200 bidons', v: '− 2 320 000', st: 'HELD' },
            { ic: 'truck', tone: 'warn', t: 'Frais transitaire', s: 'Express Logistics · Douala', v: '− 85 000', st: 'PENDING' },
            { ic: 'refresh', tone: 'coral', t: 'Remboursement litige', s: 'CMD #62B1F0', v: '+ 140 000', st: 'SUCCESS', pos: true },
          ].map((tx, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <div style={{
                width: 38, height: 38, borderRadius: 11, display: 'grid', placeItems: 'center',
                background: tx.tone === 'success' ? T.primarySoft :
                            tx.tone === 'info' ? '#E0E7FF' :
                            tx.tone === 'warn' ? T.accentSoft : T.coralSoft,
                color: tx.tone === 'success' ? T.primaryDark :
                       tx.tone === 'info' ? '#3730A3' :
                       tx.tone === 'warn' ? '#8E5A00' : T.coral,
              }}>
                <Icon name={tx.ic} size={17}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600, color: T.ink }}>{tx.t}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 2 }}>{tx.s}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: tx.pos ? T.success : T.ink, fontFeatureSettings: '"tnum"' }}>{tx.v}</div>
                <div style={{ fontSize: 9.5, color: T.ink3, marginTop: 2, letterSpacing: '.04em', fontWeight: 600 }}>{tx.st}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>

      <div style={{ height: 16 }}/>
    </div>
  );
}

function StatCard({ ic, label, value, sub, tone }) {
  const tones = {
    info:    { bg: '#E0E7FF', fg: '#3730A3' },
    success: { bg: T.primarySoft, fg: T.primaryDark },
    warn:    { bg: T.accentSoft, fg: '#8E5A00' },
  };
  const t = tones[tone];
  return (
    <div style={{
      background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 12,
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 9, background: t.bg, color: t.fg,
        display: 'grid', placeItems: 'center', marginBottom: 8,
      }}><Icon name={ic} size={16}/></div>
      <div style={{ fontSize: 10.5, color: T.ink3, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.04em' }}>{label}</div>
      <div style={{ fontSize: 17, fontWeight: 800, fontFeatureSettings: '"tnum"', marginTop: 2, letterSpacing: '-0.01em' }}>{value}</div>
      <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 2 }}>{sub}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 8) TOPUP — choose method + amount + OTP
// ─────────────────────────────────────────────────────────────
function TopupScreen({ nav }) {
  const [method, setMethod] = React.useState('mtn');
  const [amount, setAmount] = React.useState('100000');
  const presets = [25000, 50000, 100000, 250000];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('wallet')} title="Recharger" subtitle="Via NotchPay"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {/* Method */}
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11.5, fontWeight: 700, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Méthode</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {[
              { id: 'mtn', logo: 'MTN', color: '#FFCC00', dark: '#1A1A1A', name: 'MTN MoMo' },
              { id: 'om', logo: 'OM', color: '#FF6600', dark: '#fff', name: 'Orange Money' },
              { id: 'visa', logo: 'VISA', color: '#1A1F71', dark: '#fff', name: 'Carte Visa' },
              { id: 'mc', logo: 'MC', color: '#EB001B', dark: '#fff', name: 'Mastercard' },
            ].map(m => (
              <button key={m.id} onClick={() => setMethod(m.id)} style={{
                padding: 12, borderRadius: 14, background: T.surface,
                border: `1.5px solid ${method === m.id ? T.primary : T.line}`,
                boxShadow: method === m.id ? `0 0 0 4px ${T.primarySoft}` : 'none',
                cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10,
                transition: `border-color ${T.duration} ${T.ease}`,
              }}>
                <div style={{
                  width: 40, height: 26, borderRadius: 5, background: m.color, color: m.dark,
                  display: 'grid', placeItems: 'center', fontWeight: 800, fontSize: 10.5,
                }}>{m.logo}</div>
                <div style={{ fontSize: 12.5, fontWeight: 700, color: T.ink }}>{m.name}</div>
              </button>
            ))}
          </div>
        </div>

        {/* Amount entry */}
        <div style={{
          background: `linear-gradient(135deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          color: '#fff', borderRadius: 20, padding: '20px 18px', textAlign: 'center',
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{ position: 'absolute', right: -20, top: -20, width: 100, height: 100, borderRadius: '50%', background: 'rgba(245,180,0,.12)' }}/>
          <div style={{ fontSize: 11, opacity: .7, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Montant à recharger</div>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', marginTop: 10, gap: 6 }}>
            <input
              value={parseInt(amount || '0', 10).toLocaleString('fr-FR')}
              onChange={e => setAmount(e.target.value.replace(/\D/g, ''))}
              style={{
                background: 'transparent', border: 'none', outline: 'none', color: '#fff',
                fontSize: 40, fontWeight: 800, width: 200, textAlign: 'right',
                fontFamily: T.fontDisplay, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em',
              }}
            />
            <span style={{ fontSize: 13, opacity: .8, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .8, marginTop: 8 }}>
            Frais NotchPay · 1 % = {Math.round(parseInt(amount || '0', 10) * 0.01).toLocaleString('fr-FR')} FCFA
          </div>
        </div>

        {/* Preset chips */}
        <div style={{ display: 'flex', gap: 8, marginTop: 12, overflowX: 'auto', scrollbarWidth: 'none' }}>
          {presets.map(p => (
            <button key={p} onClick={() => setAmount(String(p))} style={{
              flexShrink: 0, padding: '8px 14px', borderRadius: 999,
              background: amount === String(p) ? T.ink : T.surface,
              color: amount === String(p) ? '#fff' : T.ink2,
              border: `1px solid ${amount === String(p) ? T.ink : T.line}`,
              fontSize: 12, fontWeight: 700, cursor: 'pointer',
              fontFeatureSettings: '"tnum"', whiteSpace: 'nowrap',
            }}>{p.toLocaleString('fr-FR')} FCFA</button>
          ))}
        </div>

        {/* Phone number */}
        <div style={{ marginTop: 16 }}>
          <Field label="Numéro Mobile Money" icon="phone" value="+237 6 82 14 04 82" placeholder="+237 6•• •• •• ••"/>
        </div>

        {/* Security note */}
        <div style={{
          marginTop: 14, padding: 12, background: T.primarySoft, borderRadius: 12,
          display: 'flex', alignItems: 'flex-start', gap: 10,
        }}>
          <Icon name="shieldCheck" size={18} color={T.primary} style={{ marginTop: 2 }}/>
          <div style={{ fontSize: 12, color: T.primaryDark, lineHeight: 1.5 }}>
            <b>Confirmation OTP requise.</b> Un code à 6 chiffres sera envoyé par SMS, puis votre PIN wallet sera demandé.
          </div>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('wallet')}>
          Recharger {parseInt(amount || '0', 10).toLocaleString('fr-FR')} FCFA
        </Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 9) ORDERS list
// ─────────────────────────────────────────────────────────────
function OrdersScreen({ nav }) {
  const [tab, setTab] = React.useState('cours');
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Commandes" subtitle="Suivi et historique"/>

      {/* Tabs */}
      <div style={{ padding: '0 16px 14px' }}>
        <div style={{
          display: 'flex', background: T.surface2, padding: 4, borderRadius: 12, gap: 2,
          border: `1px solid ${T.line2}`,
        }}>
          {[
            { id: 'cours', label: 'En cours', count: 2 },
            { id: 'livr', label: 'Livrées', count: 14 },
            { id: 'lit', label: 'Litiges', count: 0 },
          ].map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, padding: '8px 4px', border: 'none', cursor: 'pointer',
              background: tab === t.id ? T.surface : 'transparent',
              boxShadow: tab === t.id ? T.shadowSm : 'none',
              borderRadius: 9, fontSize: 12.5, fontWeight: 700,
              color: tab === t.id ? T.ink : T.ink2,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 5,
              transition: `background ${T.duration} ${T.ease}`,
            }}>
              {t.label}
              {t.count > 0 && <span style={{
                background: tab === t.id ? T.primary : T.surface3,
                color: tab === t.id ? '#fff' : T.ink2,
                fontSize: 10, padding: '1px 6px', borderRadius: 999, fontWeight: 800,
              }}>{t.count}</span>}
            </button>
          ))}
        </div>
      </div>

      {/* List */}
      <div style={{ padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {[
          { id: '#84F2E1B', name: 'Huile palme 20 L × 200', sup: 'Tropical Foods', total: '2 320 000', status: 'transit', date: '12 mai', tone: 'accent', icon: 'package' },
          { id: '#71A09C0', name: 'Riz long grain × 20 sacs', sup: 'Yaoundé Foods', total: '580 000', status: 'paid', date: '14 mai', tone: 'cream', icon: 'package' },
          { id: '#5DC182A', name: 'Ciment Dangote × 100', sup: 'BTP Cameroun', total: '648 000', status: 'preparing', date: '11 mai', tone: 'cream', icon: 'package' },
        ].map((o, i) => (
          <button key={i} onClick={() => nav('tracking')} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14,
            cursor: 'pointer', display: 'flex', gap: 12, textAlign: 'left',
            transition: `transform ${T.duration} ${T.ease}, box-shadow ${T.duration} ${T.ease}`,
          }}>
            <Ph icon={o.icon} height={64} radius={11} tone={o.tone}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 6 }}>
                <span style={{ fontSize: 10, color: T.ink3, fontFamily: T.fontMono, letterSpacing: '.04em' }}>CMD {o.id}</span>
                <span style={{ fontSize: 10, color: T.ink3 }}>{o.date}</span>
              </div>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: T.ink, marginTop: 3 }}>{o.name}</div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 1 }}>{o.sup}</div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 8 }}>
                {o.status === 'transit' && <Pill variant="warn" size="sm"><Icon name="truck" size={10} color="#8E5A00"/> En transit</Pill>}
                {o.status === 'paid' && <Pill variant="info" size="sm"><Icon name="shield" size={10} color="#3730A3"/> Séquestré</Pill>}
                {o.status === 'preparing' && <Pill variant="neutral" size="sm"><Icon name="clock" size={10} color={T.ink2}/> Préparation</Pill>}
                <span style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{o.total} <span style={{ fontSize: 10, color: T.ink3 }}>FCFA</span></span>
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 10) TRACKING — timeline + transitaire + actions
// ─────────────────────────────────────────────────────────────
function TrackingScreen({ nav }) {
  const steps = [
    { done: true, t: 'Commande passée', s: '12 mai · 09:42 · 2 320 000 FCFA séquestrés' },
    { done: true, t: 'Devis transitaire accepté', s: 'Express Logistics · 85 000 FCFA' },
    { done: true, t: 'Colis pris en charge', s: '13 mai · 07:30 · Entrepôt Douala' },
    { active: true, t: 'En route vers Yaoundé', s: 'Position : Edéa · ETA 18 mai' },
    { t: 'Preuve de livraison', s: 'Photo + code 4 chiffres à valider' },
    { t: 'Libération séquestre', s: 'Vendeur 92 % · Transitaire 5 % · Plateforme 3 %' },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader
        onBack={() => nav('orders')}
        title="Suivi commande"
        subtitle="CMD #84F2E1B"
        right={<><IconBtn name="share"/><IconBtn name="moreV"/></>}
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px' }}>
        {/* Hero status */}
        <div style={{
          background: `linear-gradient(135deg, ${T.accent} 0%, #FFC940 100%)`,
          color: '#1a0f00', borderRadius: 20, padding: 18,
          position: 'relative', overflow: 'hidden', boxShadow: T.shadowAccent,
        }}>
          <Icon name="truck" size={120} style={{ position: 'absolute', right: -20, bottom: -25, opacity: .14, color: '#1a0f00' }}/>
          <Pill variant="dark" size="sm">EN TRANSIT</Pill>
          <div style={{ fontFamily: T.fontDisplay, fontWeight: 800, fontSize: 22, marginTop: 8, letterSpacing: '-0.02em', lineHeight: 1.2 }}>
            Arrivée estimée<br/><span style={{ fontSize: 28 }}>lundi 18 mai</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, fontSize: 12, fontWeight: 600 }}>
            <Icon name="mapPin" size={13}/> Douala → Yaoundé · ~245 km
          </div>
        </div>

        {/* Product summary */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 12,
          marginTop: 12, display: 'flex', gap: 12, alignItems: 'center',
        }}>
          <Ph icon="package" height={56} radius={10} tone="accent"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: T.ink }}>Huile palme 20 L × 200</div>
            <div style={{ fontSize: 11, color: T.ink3, marginTop: 2 }}>Tropical Foods · KYC validé</div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>2 320 000</div>
            <div style={{ fontSize: 10, color: T.ink3 }}>FCFA</div>
          </div>
        </div>

        {/* Transitaire */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14, marginTop: 10,
        }}>
          <div style={{ fontSize: 10.5, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Transitaire</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Avatar name="Express Logistics" size={44} variant="primary"/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 700 }}>Express Logistics</div>
              <div style={{ fontSize: 11, color: T.ink3, display: 'flex', alignItems: 'center', gap: 4, marginTop: 2 }}>
                <Stars value={4.8} size={11}/> 4,8 · 1 240 livraisons
              </div>
            </div>
            <IconBtn name="phone"/>
            <IconBtn name="chat" onClick={() => nav('chat-thread')} style={{ background: T.ink, color: '#fff' }}/>
          </div>
        </div>

        {/* Timeline */}
        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 12, fontWeight: 800, color: T.ink2, marginBottom: 10, textTransform: 'uppercase', letterSpacing: '.04em' }}>Étapes de la commande</div>
          <div style={{ position: 'relative', paddingLeft: 24 }}>
            <div style={{
              position: 'absolute', left: 11, top: 8, bottom: 8, width: 2,
              background: T.line,
            }}/>
            <div style={{
              position: 'absolute', left: 11, top: 8, height: 'calc(60% - 8px)', width: 2,
              background: T.primary,
            }}/>
            {steps.map((s, i) => (
              <div key={i} style={{ position: 'relative', padding: '6px 0 18px' }}>
                <div style={{
                  position: 'absolute', left: -24, top: 6, width: 22, height: 22, borderRadius: '50%',
                  background: s.done ? T.primary : s.active ? T.accent : T.surface,
                  border: `2.5px solid ${s.done ? T.primary : s.active ? T.accent : T.line}`,
                  display: 'grid', placeItems: 'center',
                  animation: s.active ? 'pulse 1.6s ease-in-out infinite' : 'none',
                }}>
                  {s.done && <Icon name="check" size={11} color="#fff" strokeWidth={3.5}/>}
                  {s.active && <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#1a0f00' }}/>}
                </div>
                <div style={{
                  fontSize: 13.5, fontWeight: s.done || s.active ? 700 : 500,
                  color: s.done || s.active ? T.ink : T.ink3,
                }}>{s.t}</div>
                <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>{s.s}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Sticky CTA area */}
        <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
          <Btn variant="primary" size="md" icon="checkCircle" style={{ flex: 1 }}>Confirmer livraison</Btn>
          <Btn variant="outline" size="md" style={{ flex: 1 }}>Ouvrir litige</Btn>
        </div>

        <style>{`@keyframes pulse { 0%,100% { box-shadow: 0 0 0 0 rgba(245,180,0,.5);} 50% { box-shadow: 0 0 0 10px rgba(245,180,0,0);} }`}</style>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 11) CHAT LIST
// ─────────────────────────────────────────────────────────────
function ChatListScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Messagerie" subtitle="Temps réel · WebSocket" right={<IconBtn name="search"/>}/>

      <div style={{ padding: '4px 16px 12px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          background: T.surface, padding: '0 14px',
          border: `1px solid ${T.line}`, borderRadius: 14, minHeight: 44,
        }}>
          <Icon name="search" size={16} color={T.ink3}/>
          <input placeholder="Rechercher conversation…" style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 13.5 }}/>
        </div>
      </div>

      {/* Chips */}
      <div style={{ display: 'flex', gap: 8, padding: '0 16px 10px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['Tous', 'Fournisseurs', 'Transitaires', 'Support', 'Non lus 3'].map((c, i) => (
          <button key={c} style={{
            flexShrink: 0, padding: '7px 12px', borderRadius: 999,
            background: i === 0 ? T.ink : T.surface,
            color: i === 0 ? '#fff' : T.ink2,
            border: `1px solid ${i === 0 ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 600, cursor: 'pointer',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', background: T.surface, marginTop: 4 }}>
        {[
          { av: 'Tropical Foods', variant: 'primary', name: 'Tropical Foods', sub: 'Le devis transitaire est prêt, vous…', time: '2 min', unread: 3, online: true, type: 'fournisseur' },
          { av: 'Express Logistics', variant: 'accent', name: 'Express Logistics', sub: 'Colis en route, ETA lundi 18 mai', time: '11:42', unread: 0, online: true, type: 'transitaire' },
          { av: 'Yaoundé Foods', variant: 'primary', name: 'Yaoundé Foods', sub: 'Merci pour la commande. Expédition…', time: 'hier', unread: 0, type: 'fournisseur' },
          { av: 'SOTRAM Cameroun', variant: 'accent', name: 'SOTRAM Cameroun', sub: 'Vous avez 1 nouveau devis 📋', time: 'hier', unread: 1, type: 'transitaire' },
          { av: 'Support Marché', variant: 'dark', name: 'Support · Marché CM', sub: 'KYC validé, bienvenue 👋', time: 'lun.', unread: 0, type: 'support' },
        ].map((r, i, arr) => (
          <button key={i} onClick={() => nav('chat-thread')} style={{
            width: '100%', display: 'flex', gap: 12, padding: '12px 16px',
            border: 'none', background: 'transparent', cursor: 'pointer', textAlign: 'left',
            borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            alignItems: 'center',
          }}>
            <div style={{ position: 'relative' }}>
              <Avatar name={r.av} size={48} variant={r.variant}/>
              {r.online && <span style={{
                position: 'absolute', bottom: 0, right: 0, width: 13, height: 13,
                background: T.success, borderRadius: '50%', border: `2.5px solid ${T.surface}`,
              }}/>}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 14.5, fontWeight: 700, color: T.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.name}</span>
                <span style={{ fontSize: 11, color: r.unread ? T.primary : T.ink3, fontWeight: r.unread ? 700 : 500, flexShrink: 0 }}>{r.time}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
                <span style={{
                  fontSize: 12.5, color: r.unread ? T.ink : T.ink3,
                  fontWeight: r.unread ? 600 : 400,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1, minWidth: 0,
                }}>{r.sub}</span>
                {r.unread > 0 && <span style={{
                  background: T.coral, color: '#fff', fontSize: 10.5, fontWeight: 800,
                  borderRadius: 999, padding: '2px 7px', flexShrink: 0,
                  fontFeatureSettings: '"tnum"',
                }}>{r.unread}</span>}
              </div>
            </div>
          </button>
        ))}
      </div>

      {/* FAB */}
      <button onClick={() => nav('chat-thread')} style={{
        position: 'absolute', bottom: 90, right: 20,
        width: 56, height: 56, borderRadius: '50%',
        background: T.accent, color: '#1a0f00',
        border: 'none', cursor: 'pointer',
        boxShadow: T.shadowAccent,
        display: 'grid', placeItems: 'center',
      }}>
        <Icon name="edit" size={22} strokeWidth={2.3}/>
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 12) CHAT THREAD
// ─────────────────────────────────────────────────────────────
function ChatThreadScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      {/* Header */}
      <div style={{
        padding: '8px 12px 10px', display: 'flex', alignItems: 'center', gap: 10,
        background: T.surface, borderBottom: `1px solid ${T.line2}`, flexShrink: 0,
      }}>
        <IconBtn name="arrowLeft" onClick={() => nav('chat-list')} style={{ background: 'transparent', border: 'none' }}/>
        <div style={{ position: 'relative' }}>
          <Avatar name="Tropical Foods" size={38} variant="primary"/>
          <span style={{
            position: 'absolute', bottom: 0, right: 0, width: 10, height: 10,
            background: T.success, borderRadius: '50%', border: `2px solid ${T.surface}`,
          }}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14.5, fontWeight: 700, color: T.ink }}>Tropical Foods SARL</div>
          <div style={{ fontSize: 11, color: T.success, fontWeight: 600 }}>En ligne · répond en 2 h</div>
        </div>
        <IconBtn name="phone" style={{ background: 'transparent', border: 'none' }}/>
        <IconBtn name="moreV" style={{ background: 'transparent', border: 'none' }}/>
      </div>

      {/* Messages */}
      <div style={{
        flex: 1, overflow: 'auto', padding: '14px 14px', display: 'flex', flexDirection: 'column', gap: 8,
        background: `
          radial-gradient(60% 80% at 20% 0%, rgba(245,180,0,.04), transparent 60%),
          radial-gradient(60% 80% at 80% 100%, rgba(15,122,79,.04), transparent 60%),
          ${T.bg}`,
      }}>
        <div style={{ textAlign: 'center', fontSize: 11, color: T.ink3, margin: '6px 0', fontWeight: 600 }}>Aujourd'hui</div>

        <Msg from="them">Bonjour Awa 👋 Votre commande de 200 bidons est confirmée. Je sollicite un devis chez Express Logistics.</Msg>
        <Msg from="them" time="09:48"/>

        <Msg from="me">Parfait. Délai souhaité : avant le 20 mai.</Msg>
        <Msg from="me" time="09:51 · lu"/>

        <SystemMsg ic="truck">Express Logistics a soumis un devis</SystemMsg>

        {/* Quote card */}
        <div style={{ alignSelf: 'flex-start', maxWidth: '88%', background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, borderBottomLeftRadius: 4, padding: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
            <div style={{ width: 30, height: 30, borderRadius: 8, background: T.primarySoft, color: T.primary, display: 'grid', placeItems: 'center' }}>
              <Icon name="truck" size={16}/>
            </div>
            <div>
              <div style={{ fontSize: 10.5, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em' }}>Devis transitaire</div>
              <div style={{ fontSize: 12, fontWeight: 700, color: T.ink }}>Express Logistics</div>
            </div>
          </div>
          <div style={{ fontSize: 24, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>
            85 000<span style={{ fontSize: 12, color: T.ink3, marginLeft: 4, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>Douala → Yaoundé · ETA 5 j · assurance incluse</div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <Btn variant="outline" size="sm" style={{ flex: 1 }}>Décliner</Btn>
            <Btn variant="primary" size="sm" style={{ flex: 1 }} icon="check">Accepter</Btn>
          </div>
        </div>

        <Msg from="them">Le devis est dans votre commande. Validez quand vous voulez et l'enlèvement se fera dès demain matin.</Msg>
        <Msg from="them" time="10:14"/>

        <Msg from="me">Devis accepté ✅</Msg>
        <Msg from="me" time="10:16 · lu"/>

        <SystemMsg ic="shieldCheck" tone="success">Séquestre HELD · 2 320 000 FCFA bloqués</SystemMsg>
      </div>

      {/* Input */}
      <div style={{
        background: T.surface, borderTop: `1px solid ${T.line2}`,
        padding: '8px 10px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0,
      }}>
        <IconBtn name="paperclip" style={{ background: 'transparent', border: 'none' }}/>
        <div style={{
          flex: 1, background: T.surface2, borderRadius: 22, padding: '0 14px',
          display: 'flex', alignItems: 'center', gap: 8, minHeight: 44,
        }}>
          <input placeholder="Écrire un message…" style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 14 }}/>
          <Icon name="smile" size={18} color={T.ink3}/>
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

function Msg({ from, children, time }) {
  const isMe = from === 'me';
  if (time && !children) {
    return <div style={{
      alignSelf: isMe ? 'flex-end' : 'flex-start',
      fontSize: 10.5, color: T.ink3, padding: '0 12px', marginTop: -4, fontWeight: 500,
    }}>{time}</div>;
  }
  return (
    <div style={{
      alignSelf: isMe ? 'flex-end' : 'flex-start',
      maxWidth: '78%',
      padding: '9px 13px',
      borderRadius: 16,
      borderBottomRightRadius: isMe ? 4 : 16,
      borderBottomLeftRadius: isMe ? 16 : 4,
      background: isMe ? T.primary : T.surface,
      color: isMe ? '#fff' : T.ink,
      border: isMe ? 'none' : `1px solid ${T.line2}`,
      fontSize: 14, lineHeight: 1.42,
      boxShadow: isMe ? '0 1px 2px rgba(15,122,79,.2)' : T.shadowSm,
    }}>{children}</div>
  );
}

function SystemMsg({ ic, tone = 'warn', children }) {
  const palettes = {
    warn: { bg: T.accentSoft, fg: '#8E5A00' },
    success: { bg: T.primarySoft, fg: T.primaryDark },
  };
  const p = palettes[tone];
  return (
    <div style={{
      alignSelf: 'center', maxWidth: '90%', padding: '6px 12px',
      background: p.bg, color: p.fg, borderRadius: 999,
      fontSize: 11.5, fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: 6,
      letterSpacing: '.01em',
    }}>
      {ic && <Icon name={ic} size={12} color={p.fg}/>}
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 13) PROFILE
// ─────────────────────────────────────────────────────────────
function ProfileScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      {/* Curved hero */}
      <div style={{
        background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
        padding: '8px 16px 70px', borderRadius: '0 0 32px 32px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="star" size={120} color={T.accent} style={{ position: 'absolute', right: -20, top: 0, opacity: .1 }}/>
        <ScreenHeader title="Profil" dark transparent right={<IconBtn name="moreV" light style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '0 4px' }}>
          <Avatar name="Awa Kamga" size={64} variant="accent" light/>
          <div>
            <div style={{ fontSize: 18, fontFamily: T.fontDisplay, fontWeight: 800, letterSpacing: '-0.01em' }}>Awa Kamga</div>
            <div style={{ fontSize: 12, opacity: .8, marginTop: 2 }}>Acheteur · Douala 🇨🇲</div>
            <div style={{ marginTop: 6 }}>
              <Pill variant="accent" size="sm"><Icon name="shieldCheck" size={10} color="#1a0f00"/> KYC VALIDÉ</Pill>
            </div>
          </div>
        </div>
      </div>

      {/* Stats row */}
      <div style={{ padding: '0 16px', marginTop: -50, position: 'relative' }}>
        <div style={{
          background: T.surface, borderRadius: 20, padding: 16,
          border: `1px solid ${T.line}`, boxShadow: T.shadowMd,
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12,
        }}>
          <Stat v="16" l="Commandes"/>
          <Stat v="2,1 M" l="Dépensé" sep/>
          <Stat v="4,8" l="Note" star/>
        </div>
      </div>

      {/* Menu groups */}
      <div style={{ padding: '20px 16px' }}>
        <MenuGroup title="Compte" items={[
          { ic: 'user', l: 'Informations personnelles', s: 'Awa Kamga · +237 6•• ••• 482' },
          { ic: 'shieldCheck', l: 'Conformité KYC', s: 'Validé · expire 12/2026', badge: 'OK', tone: 'success' },
          { ic: 'lock', l: 'Sécurité & PIN wallet', s: 'PIN actif · 2FA SMS' },
          { ic: 'mapPin', l: 'Adresses', s: '2 adresses enregistrées' },
        ]}/>

        <MenuGroup title="Commerce" items={[
          { ic: 'package', l: 'Mes commandes', s: '2 en cours · 14 livrées', onClick: () => nav('orders') },
          { ic: 'wallet', l: 'Portefeuille', s: '1 248 500 FCFA disponibles', onClick: () => nav('wallet') },
          { ic: 'heart', l: 'Favoris', s: '23 produits enregistrés' },
          { ic: 'flag', l: 'Litiges', s: 'Aucun litige en cours' },
        ]}/>

        <MenuGroup title="Préférences" items={[
          { ic: 'bell', l: 'Notifications', s: 'WebSocket · push activé' },
          { ic: 'globe', l: 'Langue & région', s: 'Français · FCFA · Cameroun' },
          { ic: 'mountain', l: 'À propos', s: 'Marché CM v2.1' },
        ]}/>

        <button style={{
          width: '100%', marginTop: 8, padding: 14, borderRadius: 14,
          background: T.coralSoft, color: T.coral, border: 'none',
          fontWeight: 700, fontSize: 14, cursor: 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          <Icon name="arrowLeft" size={16}/> Se déconnecter
        </button>

        <div style={{ textAlign: 'center', fontSize: 10.5, color: T.ink4, marginTop: 16, padding: 4 }}>
          Marché CM v2.1 · build 2026.05.20
        </div>
      </div>
    </div>
  );
}

function Stat({ v, l, sep, star }) {
  return (
    <div style={{
      textAlign: 'center', position: 'relative',
      borderLeft: sep ? `1px solid ${T.line}` : 'none',
      borderRight: sep ? `1px solid ${T.line}` : 'none',
    }}>
      <div style={{ fontSize: 20, fontWeight: 800, fontFeatureSettings: '"tnum"', color: T.ink, letterSpacing: '-0.01em', display: 'inline-flex', alignItems: 'center', gap: 3 }}>
        {v}
        {star && <Icon name="star" size={14} color={T.accent}/>}
      </div>
      <div style={{ fontSize: 11, color: T.ink3, marginTop: 1, fontWeight: 600 }}>{l}</div>
    </div>
  );
}

function MenuGroup({ title, items }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em', padding: '0 4px 8px' }}>{title}</div>
      <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, overflow: 'hidden' }}>
        {items.map((it, i) => (
          <button key={i} onClick={it.onClick} style={{
            width: '100%', display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 14px', border: 'none', background: 'transparent', cursor: 'pointer',
            textAlign: 'left',
            borderBottom: i < items.length - 1 ? `1px solid ${T.line2}` : 'none',
            minHeight: 56,
          }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10, background: T.primarySoft, color: T.primary,
              display: 'grid', placeItems: 'center',
            }}><Icon name={it.ic} size={17}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13.5, fontWeight: 600, color: T.ink }}>{it.l}</div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 1 }}>{it.s}</div>
            </div>
            {it.badge && <Pill variant={it.tone || 'success'} size="sm">{it.badge}</Pill>}
            <Icon name="chevronR" size={16} color={T.ink3}/>
          </button>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, {
  WalletScreen, TopupScreen, OrdersScreen, TrackingScreen,
  ChatListScreen, ChatThreadScreen, ProfileScreen,
  StatCard, Msg, SystemMsg, Stat, MenuGroup,
});
