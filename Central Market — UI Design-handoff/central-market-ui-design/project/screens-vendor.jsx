/*
 * Marché CM — Vendor screens (Fournisseur / Grossiste)
 * Dashboard, Products, Product Edit, Orders, Order Detail,
 * Earnings, Stats, RFQ Inbox, Vendor Profile
 */

// ─────────────────────────────────────────────────────────────
// V-1) DASHBOARD
// ─────────────────────────────────────────────────────────────
function VDashboardScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg, paddingBottom: 16 }}>
      {/* Curved header */}
      <div style={{
        background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
        padding: '12px 16px 32px',
        borderRadius: '0 0 28px 28px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="star" size={120} color={T.accent} style={{ position: 'absolute', right: -30, top: -20, opacity: .08 }}/>
        <Icon name="mountain" size={140} color="#fff" style={{ position: 'absolute', left: -20, bottom: -50, opacity: .04 }}/>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <Avatar name="Tropical Foods" size={42} variant="accent" light/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11.5, opacity: .8, fontWeight: 600 }}>Espace vendeur</div>
            <div style={{ fontSize: 15, fontWeight: 700, fontFamily: T.fontDisplay, display: 'flex', alignItems: 'center', gap: 6 }}>
              Tropical Foods SARL
              <Pill variant="accent" size="sm">B2B</Pill>
            </div>
          </div>
          <IconBtn name="bell" light badge={5} style={{ background: 'rgba(255,255,255,.15)', border: '1px solid rgba(255,255,255,.2)' }}/>
        </div>

        <div style={{ marginTop: 18 }}>
          <div style={{ fontSize: 11, opacity: .75, fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase' }}>Chiffre d'affaires · mai 2026</div>
          <div style={{ fontSize: 34, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 2 }}>
            14,8 M<span style={{ fontSize: 14, opacity: .7, fontWeight: 600, marginLeft: 6 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .85, display: 'flex', alignItems: 'center', gap: 6, marginTop: 3 }}>
            <span style={{ background: T.accent, color: '#1a0f00', padding: '1px 7px', borderRadius: 999, fontWeight: 800, display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 11 }}>
              <Icon name="trending" size={11} strokeWidth={3} color="#1a0f00"/>+18 %
            </span>
            vs avril (12,5 M)
          </div>
        </div>
      </div>

      {/* KPI grid — overlaps curved header */}
      <div style={{ padding: '0 16px', marginTop: -18, position: 'relative' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <KpiCard ic="package" tone="success" v="42" label="Commandes" sub="ce mois" actionLabel="Voir" onAction={() => nav('v-orders')}/>
          <KpiCard ic="shield" tone="info" v="2,9 M" label="Séquestré" sub="à libérer"/>
          <KpiCard ic="scale" tone="warn" v="8" label="RFQ" sub="à traiter" actionLabel="Répondre" onAction={() => nav('v-rfq')}/>
          <KpiCard ic="trophy" tone="coral" v="4,6 ★" label="Note" sub="218 avis"/>
        </div>
      </div>

      {/* Alerts strip */}
      <div style={{ padding: '14px 16px 0' }}>
        <Alert tone="warn" ic="package" title="Stock critique" sub="Huile palme 20 L · 32 unités restantes" cta="Réapprovisionner"/>
        <Alert tone="info" ic="scale" title="3 RFQ urgentes" sub="Cacao en fèves · délai 48 h" cta="Voir" onClick={() => nav('v-rfq')}/>
      </div>

      {/* Quick actions */}
      <Section title="Actions rapides">
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10, padding: '0 16px' }}>
          <QuickAction ic="plus" label="Produit" tone="primary" onClick={() => nav('v-product-edit')}/>
          <QuickAction ic="package" label="Commandes" tone="accent" onClick={() => nav('v-orders')} badge="3"/>
          <QuickAction ic="scale" label="RFQ" tone="info" onClick={() => nav('v-rfq')}/>
          <QuickAction ic="trending" label="Stats" tone="coral" onClick={() => nav('v-stats')}/>
        </div>
      </Section>

      {/* Recent orders */}
      <Section title="Commandes récentes" action="Toutes" onAction={() => nav('v-orders')}>
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { id: '#84F2E1B', buyer: 'Awa Kamga', product: 'Huile palme 20 L × 200', amount: '2 320 000', tone: 'warn', status: 'À préparer', time: 'il y a 12 min', av: 'AK' },
            { id: '#71A09C0', buyer: 'Marché Mokolo SARL', product: 'Huile palme 20 L × 50', amount: '810 000', tone: 'success', status: 'Expédiée', time: 'hier', av: 'MM' },
            { id: '#5DC182A', buyer: 'Hotel Akwa Palace', product: 'Carton huile 1 L × 30', amount: '336 000', tone: 'info', status: 'En transit', time: '2 j', av: 'HA' },
          ].map((o, i) => (
            <button key={i} onClick={() => nav('v-order-detail')} style={{
              width: '100%', background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12,
              display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', textAlign: 'left',
            }}>
              <Avatar name={o.buyer} size={40} variant={i % 2 ? 'primary' : 'info'}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 13, fontWeight: 700, color: T.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.buyer}</span>
                  <span style={{ fontSize: 10, color: T.ink3, fontFamily: T.fontMono, flexShrink: 0 }}>{o.id}</span>
                </div>
                <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.product}</div>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 6 }}>
                  <Pill variant={o.tone} size="sm">{o.status}</Pill>
                  <span style={{ fontSize: 13, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{o.amount} <span style={{ fontSize: 9, color: T.ink3 }}>FCFA</span></span>
                </div>
              </div>
            </button>
          ))}
        </div>
      </Section>

      {/* Top products mini list */}
      <Section title="Top produits" action="Catalogue" onAction={() => nav('v-products')}>
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { name: 'Huile palme 20 L', sold: 1820, revenue: '26,4 M', tone: 'accent', icon: 'package', delta: '+24 %' },
            { name: 'Carton huile 1 L × 20', sold: 940, revenue: '10,5 M', tone: 'cream', icon: 'package', delta: '+9 %' },
            { name: 'Huile palme 5 L × 4', sold: 510, revenue: '6,2 M', tone: 'primary', icon: 'package', delta: '−3 %', neg: true },
          ].map((p, i) => (
            <div key={i} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 10,
              display: 'flex', alignItems: 'center', gap: 10,
            }}>
              <Ph icon={p.icon} height={44} radius={9} tone={p.tone}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 700 }}>{p.name}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 2 }}>{p.sold.toLocaleString('fr-FR')} unités vendues</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 13, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{p.revenue}</div>
                <div style={{ fontSize: 10.5, color: p.neg ? T.coral : T.success, fontWeight: 700, marginTop: 1 }}>{p.delta}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>
    </div>
  );
}

function KpiCard({ ic, tone, v, label, sub, actionLabel, onAction }) {
  const tones = {
    success: { bg: T.primarySoft, fg: T.primaryDark, ring: 'rgba(15,122,79,.15)' },
    info:    { bg: '#E0E7FF', fg: '#3730A3', ring: 'rgba(55,48,163,.15)' },
    warn:    { bg: T.accentSoft, fg: '#8E5A00', ring: 'rgba(142,90,0,.15)' },
    coral:   { bg: T.coralSoft, fg: T.coral, ring: 'rgba(220,38,38,.15)' },
  };
  const t = tones[tone];
  return (
    <div style={{
      background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 12,
      boxShadow: T.shadowSm,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{
          width: 32, height: 32, borderRadius: 9, background: t.bg, color: t.fg,
          display: 'grid', placeItems: 'center',
        }}><Icon name={ic} size={16}/></div>
        {actionLabel && <button onClick={onAction} style={{
          background: 'none', border: 'none', color: T.primary, fontSize: 11, fontWeight: 700, cursor: 'pointer',
        }}>{actionLabel} →</button>}
      </div>
      <div style={{ fontSize: 20, fontWeight: 800, fontFeatureSettings: '"tnum"', marginTop: 8, letterSpacing: '-0.01em' }}>{v}</div>
      <div style={{ fontSize: 11.5, color: T.ink2, fontWeight: 600 }}>{label}</div>
      <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 1 }}>{sub}</div>
    </div>
  );
}

function Alert({ tone, ic, title, sub, cta, onClick }) {
  const tones = {
    warn:  { bg: T.accentSoft, fg: '#8E5A00', icBg: T.accent, icFg: '#1a0f00' },
    info:  { bg: '#E0E7FF', fg: '#3730A3', icBg: '#4F46E5', icFg: '#fff' },
    danger:{ bg: T.coralSoft, fg: T.coral, icBg: T.coral, icFg: '#fff' },
  };
  const t = tones[tone];
  return (
    <div style={{
      background: t.bg, borderRadius: 14, padding: '10px 12px', marginBottom: 8,
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 10, background: t.icBg, color: t.icFg,
        display: 'grid', placeItems: 'center', flexShrink: 0,
      }}><Icon name={ic} size={16}/></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12.5, fontWeight: 700, color: t.fg }}>{title}</div>
        <div style={{ fontSize: 11, color: t.fg, opacity: .8, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</div>
      </div>
      {cta && <button onClick={onClick} style={{
        background: 'rgba(255,255,255,.7)', border: 'none', borderRadius: 8,
        padding: '6px 10px', fontSize: 11, fontWeight: 700, color: t.fg, cursor: 'pointer',
        flexShrink: 0,
      }}>{cta}</button>}
    </div>
  );
}

function QuickAction({ ic, label, tone, onClick, badge }) {
  const tones = {
    primary: { bg: T.primarySoft, fg: T.primary },
    accent:  { bg: T.accentSoft, fg: T.accentDark },
    info:    { bg: '#E0E7FF', fg: '#3730A3' },
    coral:   { bg: T.coralSoft, fg: T.coral },
  };
  const t = tones[tone];
  return (
    <button onClick={onClick} style={{
      background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: '12px 6px',
      cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 7,
      minHeight: 76, position: 'relative',
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: 11, background: t.bg, color: t.fg,
        display: 'grid', placeItems: 'center', position: 'relative',
      }}>
        <Icon name={ic} size={19} strokeWidth={2.2}/>
        {badge && <span style={{
          position: 'absolute', top: -4, right: -4, minWidth: 18, height: 18, padding: '0 5px',
          background: T.coral, color: '#fff', borderRadius: 9, fontSize: 10, fontWeight: 800,
          display: 'grid', placeItems: 'center', border: `2px solid ${T.surface}`,
        }}>{badge}</span>}
      </div>
      <span style={{ fontSize: 11.5, fontWeight: 600, color: T.ink2 }}>{label}</span>
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// V-2) PRODUCTS — catalog management
// ─────────────────────────────────────────────────────────────
function VProductsScreen({ nav }) {
  const [tab, setTab] = React.useState('actif');
  const products = [
    { name: 'Huile palme raffinée 20 L', sku: 'SA-22-TROP', price: '14 500', stock: 32, stockLow: true, sales: 1820, tone: 'accent', icon: 'package', status: 'actif' },
    { name: 'Carton huile cuisson 1 L × 20', sku: 'SA-LV-20', price: '11 200', stock: 240, sales: 940, tone: 'accent', icon: 'package', status: 'actif' },
    { name: 'Huile palme 5 L × pack 4', sku: 'SA-22-P5', price: '12 800', stock: 0, sales: 510, tone: 'cream', icon: 'package', status: 'rupture' },
    { name: 'Bidon huile 10 L marque Eco', sku: 'SA-10-ECO', price: '7 400', stock: 580, sales: 0, tone: 'primary', icon: 'package', status: 'brouillon' },
  ];
  const filtered = products.filter(p => p.status === tab);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader
        title="Mes produits"
        subtitle="Tropical Foods · 18 références"
        right={<><IconBtn name="search"/><IconBtn name="filter"/></>}
      />

      {/* Tabs */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          display: 'flex', background: T.surface2, padding: 4, borderRadius: 12, gap: 2,
          border: `1px solid ${T.line2}`,
        }}>
          {[
            { id: 'actif', label: 'Actifs', count: 2 },
            { id: 'rupture', label: 'Rupture', count: 1 },
            { id: 'brouillon', label: 'Brouillon', count: 1 },
          ].map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, padding: '8px 4px', border: 'none', cursor: 'pointer',
              background: tab === t.id ? T.surface : 'transparent',
              boxShadow: tab === t.id ? T.shadowSm : 'none',
              borderRadius: 9, fontSize: 12.5, fontWeight: 700,
              color: tab === t.id ? T.ink : T.ink2,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 5,
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
      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 80px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {filtered.map((p, i) => (
          <button key={i} onClick={() => nav('v-product-edit')} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12,
            cursor: 'pointer', display: 'flex', gap: 12, textAlign: 'left', alignItems: 'center',
          }}>
            <Ph icon={p.icon} height={64} radius={10} tone={p.tone}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: T.ink, lineHeight: 1.3 }}>{p.name}</div>
              <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 2, fontFamily: T.fontMono }}>SKU {p.sku}</div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 6, gap: 8 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ fontSize: 13, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{p.price}<span style={{ fontSize: 10, color: T.ink3, fontWeight: 600, marginLeft: 2 }}>FCFA</span></span>
                  <span style={{ width: 3, height: 3, borderRadius: 2, background: T.ink4 }}/>
                  <span style={{
                    fontSize: 11, fontWeight: 700,
                    color: p.stockLow ? T.coral : p.stock === 0 ? T.ink3 : T.success,
                  }}>{p.stock === 0 ? 'Épuisé' : `${p.stock} en stock${p.stockLow ? ' ⚠' : ''}`}</span>
                </div>
                <span role="button" onClick={(e) => e.stopPropagation()} style={{
                  width: 32, height: 32, borderRadius: 9, display: 'grid', placeItems: 'center',
                  color: T.ink3, cursor: 'pointer',
                }}><Icon name="moreV" size={18}/></span>
              </div>
            </div>
          </button>
        ))}
      </div>

      {/* FAB */}
      <button onClick={() => nav('v-product-edit')} style={{
        position: 'absolute', bottom: 96, right: 18,
        width: 56, height: 56, borderRadius: '50%',
        background: T.accent, color: '#1a0f00', border: 'none', cursor: 'pointer',
        boxShadow: T.shadowAccent,
        display: 'grid', placeItems: 'center',
      }}>
        <Icon name="plus" size={24} strokeWidth={2.6}/>
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-3) PRODUCT EDIT
// ─────────────────────────────────────────────────────────────
function VProductEditScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader
        onBack={() => nav('v-products')}
        title="Éditer le produit"
        right={<IconBtn name="moreV"/>}
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {/* Image grid */}
        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 11.5, fontWeight: 700, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Photos & vidéo</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            {[0, 1, 2].map(i => (
              <div key={i} style={{
                aspectRatio: '1 / 1', borderRadius: 12, background: i === 0 ? T.accentSoft : T.surface,
                border: `1px solid ${T.line}`, position: 'relative', overflow: 'hidden',
                display: 'grid', placeItems: 'center', color: i === 0 ? T.accentDark : T.ink3,
              }}>
                <Icon name="package" size={28} strokeWidth={1.4}/>
                {i === 0 && <span style={{
                  position: 'absolute', top: 4, left: 4, padding: '2px 6px', background: T.ink, color: '#fff',
                  fontSize: 9, fontWeight: 800, borderRadius: 5, letterSpacing: '.04em',
                }}>PRIMARY</span>}
                <button style={{
                  position: 'absolute', top: 4, right: 4, width: 22, height: 22, borderRadius: 6,
                  background: 'rgba(0,0,0,.5)', color: '#fff', border: 'none', cursor: 'pointer',
                  display: 'grid', placeItems: 'center',
                }}><Icon name="x" size={12} strokeWidth={2.5}/></button>
              </div>
            ))}
            <button style={{
              aspectRatio: '1 / 1', borderRadius: 12,
              background: T.surface, border: `1.5px dashed ${T.line}`,
              cursor: 'pointer', display: 'grid', placeItems: 'center', color: T.ink3,
            }}>
              <div style={{ textAlign: 'center' }}>
                <Icon name="camera" size={20}/>
                <div style={{ fontSize: 9.5, fontWeight: 700, marginTop: 4 }}>AJOUTER</div>
              </div>
            </button>
          </div>
        </div>

        {/* Name */}
        <Field label="Nom du produit" placeholder="Ex. Huile de palme 20 L"
          value="Huile de palme raffinée — bidon 20 L"/>

        {/* Category + brand */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginTop: 12 }}>
          <SelectField label="Catégorie" value="Agroalimentaire"/>
          <SelectField label="Marque" value="Tropical"/>
        </div>

        {/* Description */}
        <div style={{ marginTop: 12 }}>
          <label style={{ fontSize: 12, fontWeight: 700, color: T.ink2, marginLeft: 4, marginBottom: 6, display: 'block' }}>Description</label>
          <textarea defaultValue="Huile de palme 100 % végétale, raffinée et désodorisée. Conditionnée en bidons hermétiques de 20 L pour restaurants et commerces. Origine Cameroun, certifié RSPO." style={{
            width: '100%', padding: 12, borderRadius: 14,
            border: `1.5px solid ${T.line}`, background: T.surface,
            fontSize: 13.5, color: T.ink, fontFamily: T.fontBody,
            minHeight: 80, resize: 'vertical', outline: 'none', lineHeight: 1.5,
          }}/>
        </div>

        {/* Pricing tiers */}
        <div style={{ marginTop: 14, padding: 14, background: T.accentSoft, borderRadius: 14, border: '1px solid #F0E2BB' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
            <span style={{ fontSize: 12.5, fontWeight: 800, color: '#8E5A00', textTransform: 'uppercase', letterSpacing: '.04em' }}>Prix par paliers B2B</span>
            <button style={{ background: 'none', border: 'none', color: T.primary, fontSize: 12, fontWeight: 700, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 3 }}>
              <Icon name="plus" size={12} strokeWidth={2.5}/>Palier
            </button>
          </div>
          {[
            { q: '50 — 199', p: '16 200' },
            { q: '200 — 999', p: '14 500' },
            { q: '1 000 — 5 000', p: '12 800' },
          ].map((t, i) => (
            <div key={i} style={{
              display: 'flex', gap: 8, padding: '8px 0',
              borderTop: i ? '1px dashed rgba(122,92,14,.2)' : 'none',
              alignItems: 'center',
            }}>
              <div style={{ flex: 1, background: 'rgba(255,255,255,.6)', padding: '8px 10px', borderRadius: 8, fontSize: 12, color: T.ink2, fontFamily: T.fontMono }}>{t.q}</div>
              <div style={{ flex: 1, background: 'rgba(255,255,255,.6)', padding: '8px 10px', borderRadius: 8, fontSize: 12, color: T.ink, fontWeight: 700, fontFeatureSettings: '"tnum"' }}>{t.p} FCFA</div>
              <button style={{ background: 'transparent', border: 'none', color: T.ink3, cursor: 'pointer', padding: 4 }}>
                <Icon name="trash" size={14}/>
              </button>
            </div>
          ))}
        </div>

        {/* Stock */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginTop: 12 }}>
          <Field label="Stock disponible" value="32" placeholder="0"/>
          <Field label="Stock minimum" value="50" placeholder="0"/>
        </div>

        {/* Toggles */}
        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12 }}>
          <ToggleRow icon="globe" label="Visible dans le catalogue" sub="Découvrable par tous les acheteurs" on/>
          <div style={{ height: 1, background: T.line2, margin: '4px 0' }}/>
          <ToggleRow icon="flame" label="Marquer en promotion" sub="−15 % visible 7 jours" on={false}/>
          <div style={{ height: 1, background: T.line2, margin: '4px 0' }}/>
          <ToggleRow icon="shieldCheck" label="Vendu via séquestre uniquement" sub="Obligatoire pour B2B > 100 k" on/>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '10px 14px', display: 'flex', gap: 8, flexShrink: 0 }}>
        <Btn variant="outline" size="md" style={{ flex: 1 }}>Brouillon</Btn>
        <Btn variant="primary" size="md" icon="check" style={{ flex: 2 }} onClick={() => nav('v-products')}>Publier</Btn>
      </div>
    </div>
  );
}

function SelectField({ label, value }) {
  return (
    <div>
      <label style={{ fontSize: 12, fontWeight: 700, color: T.ink2, marginLeft: 4, marginBottom: 6, display: 'block' }}>{label}</label>
      <button style={{
        width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        background: T.surface, padding: '0 14px',
        border: `1.5px solid ${T.line}`, borderRadius: 14,
        minHeight: 52, cursor: 'pointer', fontSize: 14, color: T.ink, fontWeight: 600,
      }}>
        <span>{value}</span>
        <Icon name="chevronD" size={16} color={T.ink3}/>
      </button>
    </div>
  );
}

function ToggleRow({ icon, label, sub, on }) {
  const [v, setV] = React.useState(on);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 4px' }}>
      <div style={{
        width: 34, height: 34, borderRadius: 9, background: T.primarySoft, color: T.primary,
        display: 'grid', placeItems: 'center',
      }}><Icon name={icon} size={16}/></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: T.ink }}>{label}</div>
        <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{sub}</div>
      </div>
      <button onClick={() => setV(!v)} style={{
        width: 44, height: 26, borderRadius: 999,
        background: v ? T.primary : T.surface3, border: 'none', cursor: 'pointer',
        position: 'relative',
        transition: `background ${T.duration} ${T.ease}`,
      }}>
        <span style={{
          position: 'absolute', top: 3, left: v ? 21 : 3, width: 20, height: 20,
          borderRadius: '50%', background: '#fff',
          boxShadow: '0 1px 3px rgba(0,0,0,.2)',
          transition: `left ${T.duration} ${T.ease}`,
        }}/>
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-4) ORDERS RECEIVED
// ─────────────────────────────────────────────────────────────
function VOrdersScreen({ nav }) {
  const [tab, setTab] = React.useState('nouveau');
  const orders = {
    nouveau: [
      { id: '#84F2E1B', buyer: 'Awa Kamga', city: 'Douala', product: 'Huile palme 20 L × 200', amount: '2 320 000', time: 'il y a 12 min', av: 'AK', urgent: true },
      { id: '#9F2C8E1', buyer: 'Restaurant La Falaise', city: 'Yaoundé', product: 'Carton huile 1 L × 50', amount: '560 000', time: '38 min', av: 'RF' },
    ],
    prepa: [
      { id: '#5DC182A', buyer: 'Hotel Akwa Palace', city: 'Douala', product: 'Carton huile 1 L × 30', amount: '336 000', time: '2 j', av: 'HA' },
    ],
    expedie: [
      { id: '#71A09C0', buyer: 'Marché Mokolo', city: 'Yaoundé', product: 'Huile palme 20 L × 50', amount: '810 000', time: 'hier', av: 'MM' },
    ],
    livre: [],
  };
  const tabs = [
    { id: 'nouveau', label: 'Nouvelles', count: orders.nouveau.length },
    { id: 'prepa', label: 'Préparer', count: orders.prepa.length },
    { id: 'expedie', label: 'Expédiées', count: orders.expedie.length },
    { id: 'livre', label: 'Livrées', count: 14 },
  ];
  const list = orders[tab];

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Commandes" subtitle="Reçues · à traiter" right={<IconBtn name="filter"/>}/>

      {/* Scrollable tabs */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          display: 'flex', gap: 6, overflowX: 'auto', scrollbarWidth: 'none',
          background: T.surface2, padding: 4, borderRadius: 12, border: `1px solid ${T.line2}`,
        }}>
          {tabs.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: '1 0 auto', padding: '8px 12px', border: 'none', cursor: 'pointer',
              background: tab === t.id ? T.surface : 'transparent',
              boxShadow: tab === t.id ? T.shadowSm : 'none',
              borderRadius: 9, fontSize: 12, fontWeight: 700,
              color: tab === t.id ? T.ink : T.ink2,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 5,
              whiteSpace: 'nowrap',
            }}>
              {t.label}
              {t.count > 0 && <span style={{
                background: tab === t.id ? T.primary : T.surface3,
                color: tab === t.id ? '#fff' : T.ink2,
                fontSize: 9.5, padding: '1px 6px', borderRadius: 999, fontWeight: 800,
              }}>{t.count}</span>}
            </button>
          ))}
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {list.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 40, color: T.ink3 }}>
            <Icon name="package" size={48} color={T.surface3} style={{ margin: '0 auto' }}/>
            <div style={{ fontSize: 14, fontWeight: 700, color: T.ink2, marginTop: 12 }}>Aucune commande</div>
            <div style={{ fontSize: 12, marginTop: 4 }}>Tout est à jour 🎉</div>
          </div>
        ) : list.map((o, i) => (
          <button key={i} onClick={() => nav('v-order-detail')} style={{
            width: '100%', background: T.surface,
            border: `1px solid ${o.urgent ? T.accent : T.line}`,
            borderRadius: 16, padding: 14, cursor: 'pointer', textAlign: 'left',
            display: 'flex', flexDirection: 'column', gap: 10,
            boxShadow: o.urgent ? `0 0 0 3px ${T.accentSoft}` : 'none',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Avatar name={o.buyer} size={42} variant={i % 2 ? 'primary' : 'info'}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ fontSize: 14, fontWeight: 700, color: T.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.buyer}</span>
                  {o.urgent && <Pill variant="accent" size="sm">URGENT</Pill>}
                </div>
                <div style={{ fontSize: 11, color: T.ink3, display: 'flex', alignItems: 'center', gap: 4, marginTop: 2 }}>
                  <Icon name="mapPin" size={11}/> {o.city} · {o.time}
                </div>
              </div>
              <span style={{ fontSize: 10, color: T.ink3, fontFamily: T.fontMono }}>{o.id}</span>
            </div>
            <div style={{
              padding: '8px 10px', background: T.surface2, borderRadius: 10,
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            }}>
              <span style={{ fontSize: 12.5, color: T.ink2, fontWeight: 600 }}>{o.product}</span>
              <span style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{o.amount} <span style={{ fontSize: 10, color: T.ink3 }}>FCFA</span></span>
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              <Pill variant="info" size="sm"><Icon name="shield" size={10} color="#3730A3"/> Séquestré</Pill>
              {tab === 'nouveau' && <Btn variant="primary" size="sm" style={{ marginLeft: 'auto', minHeight: 32, padding: '4px 12px' }}>Accepter →</Btn>}
              {tab === 'prepa' && <Btn variant="accent" size="sm" style={{ marginLeft: 'auto', minHeight: 32, padding: '4px 12px' }}>Préparé</Btn>}
              {tab === 'expedie' && <Pill variant="warn" size="sm" style={{ marginLeft: 'auto' }}>En transit</Pill>}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-5) ORDER DETAIL (vendor view) — handle the order
// ─────────────────────────────────────────────────────────────
function VOrderDetailScreen({ nav }) {
  const [stage, setStage] = React.useState(1); // 0 accepted, 1 request quote, 2 ready, 3 shipped
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader
        onBack={() => nav('v-orders')}
        title="CMD #84F2E1B"
        subtitle="12 mai 2026 · 09:42"
        right={<><IconBtn name="chat" onClick={() => nav('chat-thread')}/><IconBtn name="moreV"/></>}
      />

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px' }}>
        {/* Buyer card */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 12,
          display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12,
        }}>
          <Avatar name="Awa Kamga" size={44} variant="info"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ fontSize: 14, fontWeight: 700 }}>Awa Kamga</span>
              <Pill variant="success" size="sm"><Icon name="shieldCheck" size={10} color={T.primaryDark}/> KYC</Pill>
            </div>
            <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2, display: 'flex', alignItems: 'center', gap: 4 }}>
              <Icon name="mapPin" size={11}/> Douala · 16 commandes
            </div>
          </div>
          <IconBtn name="phone"/>
          <IconBtn name="chat" onClick={() => nav('chat-thread')} style={{ background: T.ink, color: '#fff' }}/>
        </div>

        {/* Money summary */}
        <div style={{
          background: `linear-gradient(135deg, ${T.accent} 0%, #FFC940 100%)`,
          color: '#1a0f00', borderRadius: 18, padding: 16,
          position: 'relative', overflow: 'hidden',
        }}>
          <Icon name="shield" size={120} style={{ position: 'absolute', right: -25, bottom: -25, opacity: .1, color: '#1a0f00' }}/>
          <Pill variant="dark" size="sm">SÉQUESTRE HELD</Pill>
          <div style={{ fontSize: 28, fontWeight: 800, fontFeatureSettings: '"tnum"', marginTop: 6, letterSpacing: '-0.02em' }}>
            2 320 000<span style={{ fontSize: 13, marginLeft: 4, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, fontWeight: 600, opacity: .85, marginTop: 4 }}>
            Vous recevrez 2 134 400 FCFA après libération (92 %)
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 6, marginTop: 14 }}>
            {[
              { l: 'Votre part', v: '92 %' },
              { l: 'Transitaire', v: '5 %' },
              { l: 'Plateforme', v: '3 %' },
            ].map((x, i) => (
              <div key={i} style={{ background: 'rgba(255,255,255,.5)', borderRadius: 8, padding: '6px 8px' }}>
                <div style={{ fontSize: 9.5, opacity: .65, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>{x.l}</div>
                <div style={{ fontSize: 13, fontWeight: 800, marginTop: 1 }}>{x.v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Product line */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12,
          marginTop: 12, display: 'flex', gap: 12, alignItems: 'center',
        }}>
          <Ph icon="package" height={52} radius={9} tone="accent"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Huile palme 20 L × 200</div>
            <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>14 500 FCFA × 200 · palier B2B</div>
          </div>
        </div>

        {/* Action steps */}
        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Actions à faire</div>
          <StepRow done idx={1} title="Commande acceptée" sub="12 mai · 09:50"/>
          <StepRow done={stage > 1} active={stage === 1} idx={2}
            title="Demander un devis transitaire"
            sub="Express Logistics répond généralement en 2 h"
            cta={stage === 1 ? "Envoyer la demande" : null}
            onCta={() => setStage(2)}/>
          <StepRow done={stage > 2} active={stage === 2} idx={3}
            title="Préparer la marchandise"
            sub="200 bidons · entrepôt Douala"
            cta={stage === 2 ? "Marquer prêt" : null}
            onCta={() => setStage(3)}/>
          <StepRow active={stage === 3} idx={4}
            title="Remettre au transitaire"
            sub="Scanner le QR Express Logistics"
            cta={stage === 3 ? "Scanner QR" : null}/>
          <StepRow idx={5} title="Livraison à l'acheteur" sub="Preuve photo + code 4 chiffres"/>
          <StepRow idx={6} title="Libération du paiement" sub="2 134 400 FCFA → votre wallet" final/>
        </div>
      </div>
    </div>
  );
}

function StepRow({ idx, title, sub, done, active, cta, onCta, final }) {
  return (
    <div style={{
      display: 'flex', gap: 12, padding: '12px 14px', marginBottom: 8,
      background: active ? T.accentSoft : T.surface,
      border: `1px solid ${active ? T.accent : T.line}`,
      borderRadius: 14,
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: '50%', flexShrink: 0,
        background: done ? T.primary : active ? T.accent : T.surface,
        border: `2px solid ${done ? T.primary : active ? T.accent : T.line}`,
        color: done ? '#fff' : active ? '#1a0f00' : T.ink3,
        display: 'grid', placeItems: 'center',
        fontSize: 12, fontWeight: 800,
      }}>
        {done ? <Icon name="check" size={13} strokeWidth={3} color="#fff"/> : idx}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 700, color: done || active ? T.ink : T.ink3 }}>{title}</div>
        <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>{sub}</div>
        {cta && (
          <Btn variant={final ? 'accent' : 'primary'} size="sm" style={{ marginTop: 8 }} onClick={onCta}>
            {cta}
          </Btn>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-6) EARNINGS / WALLET
// ─────────────────────────────────────────────────────────────
function VEarningsScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Revenus" subtitle="Wallet vendeur"/>

      {/* Earnings card */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          background: `linear-gradient(140deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          borderRadius: 22, padding: 20, color: '#fff', position: 'relative', overflow: 'hidden',
          boxShadow: T.shadowBrand,
        }}>
          <Icon name="trending" size={120} color={T.accent} style={{ position: 'absolute', right: -28, top: -20, opacity: .1 }}/>
          <div style={{ fontSize: 11, opacity: .8, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Disponible pour retrait</div>
          <div style={{ fontSize: 32, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 4 }}>
            8 420 000<span style={{ fontSize: 14, opacity: .7, marginLeft: 6, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ marginTop: 16, display: 'flex', gap: 8 }}>
            <Btn variant="accent" size="md" icon="arrowRight" style={{ flex: 1 }}>Retirer</Btn>
            <IconBtn name="qr" light style={{ background: 'rgba(255,255,255,.15)', border: '1px solid rgba(255,255,255,.2)' }}/>
          </div>
        </div>
      </div>

      {/* Pending stats */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px 14px' }}>
        <StatCard ic="shield" label="En séquestre" value="2 900 000" sub="3 commandes" tone="info"/>
        <StatCard ic="clock" label="Cette semaine" value="+ 1,2 M" sub="à libérer" tone="warn"/>
      </div>

      {/* Mini chart */}
      <Section title="Revenus · 7 derniers jours">
        <div style={{ padding: '0 16px' }}>
          <div style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16,
          }}>
            <MiniChart values={[0.45, 0.62, 0.38, 0.72, 0.55, 0.88, 1.0]} labels={['L','M','M','J','V','S','D']}/>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 14 }}>
              <div>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Total semaine</div>
                <div style={{ fontSize: 22, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>3,8 M <span style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>FCFA</span></div>
              </div>
              <Pill variant="success"><Icon name="trending" size={11} color={T.primaryDark} strokeWidth={3}/>+22 %</Pill>
            </div>
          </div>
        </div>
      </Section>

      {/* Payout history */}
      <Section title="Historique paiements" action="Voir tout">
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, margin: '0 16px', overflow: 'hidden' }}>
          {[
            { t: 'Retrait MTN Mobile Money', s: '+237 6•• ••• 482 · 09 mai', v: '− 3 200 000', st: 'SUCCESS' },
            { t: 'Libération séquestre #4A1', s: 'Hôtel Akwa Palace', v: '+ 308 000', st: 'RELEASED', pos: true },
            { t: 'Libération séquestre #62B', s: 'Marché Mokolo', v: '+ 745 200', st: 'RELEASED', pos: true },
            { t: 'Retrait Orange Money', s: '+237 6•• ••• 119 · 02 mai', v: '− 1 800 000', st: 'SUCCESS' },
          ].map((tx, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10, display: 'grid', placeItems: 'center',
                background: tx.pos ? T.primarySoft : T.surface2,
                color: tx.pos ? T.primaryDark : T.ink2,
              }}>
                <Icon name={tx.pos ? 'shieldCheck' : 'arrowRight'} size={16}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600, color: T.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.t}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{tx.s}</div>
              </div>
              <div style={{ textAlign: 'right', flexShrink: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: tx.pos ? T.success : T.ink, fontFeatureSettings: '"tnum"' }}>{tx.v}</div>
                <div style={{ fontSize: 9.5, color: T.ink3, marginTop: 1, fontWeight: 600, letterSpacing: '.04em' }}>{tx.st}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>
      <div style={{ height: 16 }}/>
    </div>
  );
}

function MiniChart({ values, labels }) {
  const w = 320, h = 96, pad = 4;
  const stepX = (w - pad * 2) / (values.length - 1);
  const points = values.map((v, i) => [pad + i * stepX, h - pad - v * (h - pad * 2)]);
  const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p[0]},${p[1]}`).join(' ');
  const areaD = `M ${pad},${h - pad} ${pathD.slice(1)} L ${w - pad},${h - pad} Z`;
  return (
    <div>
      <svg viewBox={`0 0 ${w} ${h + 18}`} width="100%" height="auto" style={{ display: 'block' }}>
        <defs>
          <linearGradient id="vChart" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={T.primary} stopOpacity="0.25"/>
            <stop offset="1" stopColor={T.primary} stopOpacity="0"/>
          </linearGradient>
        </defs>
        <path d={areaD} fill="url(#vChart)"/>
        <path d={pathD} fill="none" stroke={T.primary} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
        {points.map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r={i === values.length - 1 ? 5 : 2.5} fill={T.surface} stroke={T.primary} strokeWidth="2"/>
        ))}
        {labels.map((l, i) => (
          <text key={i} x={pad + i * stepX} y={h + 12} fontSize="10" fontFamily="'Plus Jakarta Sans'" textAnchor="middle" fill={T.ink3} fontWeight="600">{l}</text>
        ))}
      </svg>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-7) STATS / ANALYTICS
// ─────────────────────────────────────────────────────────────
function VStatsScreen({ nav }) {
  const [period, setPeriod] = React.useState('30j');
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg, paddingBottom: 16 }}>
      <ScreenHeader title="Statistiques" subtitle="Tropical Foods" right={<IconBtn name="share"/>}/>

      {/* Period segment */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          display: 'flex', background: T.surface2, padding: 4, borderRadius: 11, gap: 2,
          border: `1px solid ${T.line2}`,
        }}>
          {[
            { id: '7j', label: '7 j' },
            { id: '30j', label: '30 j' },
            { id: '90j', label: '90 j' },
            { id: '12m', label: '12 mois' },
          ].map(p => (
            <button key={p.id} onClick={() => setPeriod(p.id)} style={{
              flex: 1, padding: '7px 4px', border: 'none', cursor: 'pointer',
              background: period === p.id ? T.surface : 'transparent',
              boxShadow: period === p.id ? T.shadowSm : 'none',
              borderRadius: 8, fontSize: 12, fontWeight: 700,
              color: period === p.id ? T.ink : T.ink2,
            }}>{p.label}</button>
          ))}
        </div>
      </div>

      {/* Revenue big card */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 18, padding: 16,
        }}>
          <div style={{ fontSize: 11, color: T.ink3, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase' }}>Chiffre d'affaires</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 4 }}>
            <span style={{ fontSize: 28, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.02em' }}>14 820 000</span>
            <span style={{ fontSize: 12, color: T.ink3, fontWeight: 600 }}>FCFA</span>
          </div>
          <Pill variant="success" size="sm" style={{ marginTop: 4 }}>
            <Icon name="trending" size={10} color={T.primaryDark} strokeWidth={3}/>+18 % vs période précédente
          </Pill>
          <div style={{ marginTop: 16 }}>
            <MiniChart values={[0.35, 0.42, 0.58, 0.48, 0.62, 0.7, 0.55, 0.78, 0.65, 0.82, 0.9, 1.0]} labels={['J1','J3','J5','J7','J9','J11','J13','J15','J17','J19','J21','J23']}/>
          </div>
        </div>
      </div>

      {/* Quick KPIs */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px 14px' }}>
        <KpiCard ic="package" tone="success" v="42" label="Commandes" sub="ce mois"/>
        <KpiCard ic="user" tone="info" v="28" label="Acheteurs" sub="dont 6 nouveaux"/>
        <KpiCard ic="trophy" tone="warn" v="4,6 ★" label="Note moyenne" sub="218 avis"/>
        <KpiCard ic="bag" tone="coral" v="92 %" label="Taux d'acceptation" sub="livraison à temps"/>
      </div>

      {/* Top products */}
      <Section title="Produits performants">
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { name: 'Huile palme 20 L', units: 1820, rev: 8400000, pct: 100, tone: 'accent' },
            { name: 'Carton huile 1 L × 20', units: 940, rev: 4200000, pct: 50, tone: 'accent' },
            { name: 'Huile palme 5 L × 4', units: 510, rev: 1500000, pct: 18, tone: 'primary' },
            { name: 'Bidon huile 10 L Eco', units: 90, rev: 470000, pct: 5, tone: 'cream' },
          ].map((p, i) => (
            <div key={i} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Ph icon="package" height={36} radius={8} tone={p.tone}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 12.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</div>
                  <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{p.units.toLocaleString('fr-FR')} unités</div>
                </div>
                <div style={{ textAlign: 'right', flexShrink: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{(p.rev / 1000).toFixed(0)}k</div>
                  <div style={{ fontSize: 10, color: T.ink3 }}>FCFA</div>
                </div>
              </div>
              <div style={{ marginTop: 6, height: 4, background: T.surface2, borderRadius: 2 }}>
                <div style={{ width: `${p.pct}%`, height: '100%', background: T.primary, borderRadius: 2, transition: `width ${T.durationMd} ${T.ease}` }}/>
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* Buyer mix donut-like */}
      <Section title="Mix acheteurs">
        <div style={{ padding: '0 16px' }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16, display: 'flex', alignItems: 'center', gap: 16 }}>
            <Donut segs={[
              { v: 62, color: T.primary, l: 'B2B Pro' },
              { v: 24, color: T.accent, l: 'Détail' },
              { v: 14, color: T.info, l: 'Hôtels' },
            ]}/>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[
                { c: T.primary, l: 'B2B Pro', v: '62 %', a: '9,2 M' },
                { c: T.accent, l: 'Détail', v: '24 %', a: '3,5 M' },
                { c: T.info, l: 'Hôtels & restos', v: '14 %', a: '2,1 M' },
              ].map((x, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
                  <span style={{ width: 9, height: 9, borderRadius: 2, background: x.c }}/>
                  <span style={{ flex: 1, color: T.ink2, fontWeight: 600 }}>{x.l}</span>
                  <span style={{ fontWeight: 700, fontFeatureSettings: '"tnum"' }}>{x.v}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </Section>
    </div>
  );
}

function Donut({ segs, centerValue, centerLabel }) {
  const total = segs.reduce((s, x) => s + x.v, 0);
  const r = 36, cx = 50, cy = 50, c = 2 * Math.PI * r;
  let offset = 0;
  const cv = centerValue != null ? centerValue : '42';
  const cl = centerLabel != null ? centerLabel : 'commandes';
  return (
    <svg viewBox="0 0 100 100" width="100" height="100">
      <circle cx={cx} cy={cy} r={r} fill="none" stroke={T.surface2} strokeWidth="14"/>
      {segs.map((s, i) => {
        const len = (s.v / total) * c;
        const el = (
          <circle key={i} cx={cx} cy={cy} r={r} fill="none" stroke={s.color} strokeWidth="14"
            strokeDasharray={`${len} ${c - len}`} strokeDashoffset={-offset}
            transform={`rotate(-90 ${cx} ${cy})`} strokeLinecap="butt"/>
        );
        offset += len;
        return el;
      })}
      <text x={cx} y={cy + 2} textAnchor="middle" fontSize="11" fontWeight="800" fill={T.ink} fontFamily="'Plus Jakarta Sans'">{cv}</text>
      <text x={cx} y={cy + 13} textAnchor="middle" fontSize="7" fill={T.ink3} fontFamily="'Plus Jakarta Sans'" fontWeight="600">{cl}</text>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// V-8) RFQ INBOX
// ─────────────────────────────────────────────────────────────
function VRfqScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('v-dashboard')} title="Demandes de devis" subtitle="8 RFQ à traiter" right={<IconBtn name="filter"/>}/>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {[
          { buyer: 'Restaurant La Falaise', city: 'Yaoundé', product: 'Huile de palme 20 L', qty: '120 bidons', deadline: '48 h', av: 'RF', urgent: true, type: 'B2B', verified: true },
          { buyer: 'Hôtel Atlantique', city: 'Kribi', product: 'Carton huile 1 L × 20', qty: '40 cartons', deadline: '5 j', av: 'HA', verified: true, type: 'Hôtel' },
          { buyer: 'Mama Ngozi', city: 'Bafoussam', product: 'Huile palme 5 L', qty: '15 unités', deadline: '24 h', av: 'MN', type: 'Détail' },
        ].map((r, i) => (
          <div key={i} style={{
            background: T.surface,
            border: `1px solid ${r.urgent ? T.coral : T.line}`,
            borderRadius: 16, padding: 14,
            boxShadow: r.urgent ? `0 0 0 3px ${T.coralSoft}` : 'none',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Avatar name={r.buyer} size={42} variant="info"/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                  <span style={{ fontSize: 13.5, fontWeight: 700 }}>{r.buyer}</span>
                  {r.verified && <Icon name="shieldCheck" size={12} color={T.primary}/>}
                </div>
                <div style={{ fontSize: 11, color: T.ink3, display: 'flex', alignItems: 'center', gap: 4, marginTop: 2 }}>
                  <Icon name="mapPin" size={10}/> {r.city} · {r.type}
                </div>
              </div>
              {r.urgent && <Pill variant="danger" size="sm">URGENT · {r.deadline}</Pill>}
              {!r.urgent && <Pill variant="neutral" size="sm">{r.deadline}</Pill>}
            </div>

            <div style={{ marginTop: 10, padding: '10px 12px', background: T.surface2, borderRadius: 10 }}>
              <div style={{ fontSize: 10.5, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>Demande</div>
              <div style={{ fontSize: 13, fontWeight: 700, marginTop: 2, color: T.ink }}>{r.product}</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 6, fontSize: 11.5, color: T.ink2 }}>
                <span><Icon name="scale" size={11} style={{ display: 'inline', marginRight: 4, verticalAlign: 'middle' }}/>{r.qty}</span>
                <span><Icon name="truck" size={11} style={{ display: 'inline', marginRight: 4, verticalAlign: 'middle' }}/>Livraison incluse</span>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
              <Btn variant="outline" size="sm" style={{ flex: 1 }} onClick={() => nav('chat-thread')}>Discuter</Btn>
              <Btn variant="primary" size="sm" iconRight="arrowRight" style={{ flex: 2 }}>Envoyer une offre</Btn>
            </div>
          </div>
        ))}

        {/* Empty state hint */}
        <div style={{
          textAlign: 'center', padding: '20px 0 8px', color: T.ink3, fontSize: 12,
        }}>
          5 RFQ déjà répondues ce mois · <a style={{ color: T.primary, fontWeight: 700 }}>Voir historique</a>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V-9) VENDOR PROFILE
// ─────────────────────────────────────────────────────────────
function VProfileScreen({ nav, onSwitchRole }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      {/* Curved hero */}
      <div style={{
        background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
        padding: '8px 16px 70px', borderRadius: '0 0 32px 32px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="trophy" size={140} color={T.accent} style={{ position: 'absolute', right: -30, top: 0, opacity: .08 }}/>
        <ScreenHeader title="Profil vendeur" dark transparent right={<IconBtn name="moreV" light style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '0 4px' }}>
          <Avatar name="Tropical Foods" size={64} variant="accent" light/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 17, fontFamily: T.fontDisplay, fontWeight: 800, letterSpacing: '-0.01em' }}>Tropical Foods SARL</div>
            <div style={{ fontSize: 12, opacity: .8, marginTop: 2 }}>Grossiste · Douala 🇨🇲</div>
            <div style={{ marginTop: 6, display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <Pill variant="accent" size="sm"><Icon name="shieldCheck" size={10} color="#1a0f00"/> KYC VALIDÉ</Pill>
              <Pill variant="dark" size="sm">★ 4,6</Pill>
            </div>
          </div>
        </div>
      </div>

      {/* Stats card */}
      <div style={{ padding: '0 16px', marginTop: -50, position: 'relative' }}>
        <div style={{
          background: T.surface, borderRadius: 20, padding: 16,
          border: `1px solid ${T.line}`, boxShadow: T.shadowMd,
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12,
        }}>
          <Stat v="18" l="Produits"/>
          <Stat v="42" l="Commandes" sep/>
          <Stat v="14,8M" l="CA mai"/>
        </div>
      </div>

      <div style={{ padding: '20px 16px' }}>
        <MenuGroup title="Boutique" items={[
          { ic: 'package', l: 'Mon catalogue', s: '18 produits actifs', onClick: () => nav('v-products') },
          { ic: 'tag', l: 'Promotions', s: '2 promos actives' },
          { ic: 'scale', l: 'RFQ entrantes', s: '8 à traiter', badge: '8', tone: 'warn', onClick: () => nav('v-rfq') },
          { ic: 'flame', l: 'Campagnes publicitaires', s: '1 active · 3 brouillons' },
        ]}/>

        <MenuGroup title="Entreprise" items={[
          { ic: 'shieldCheck', l: 'Documents KYC', s: 'Validé · expire 12/2026', badge: 'OK', tone: 'success' },
          { ic: 'mapPin', l: 'Adresses & entrepôts', s: '2 entrepôts · Douala, Yaoundé' },
          { ic: 'truck', l: 'Transitaires favoris', s: '3 partenaires enregistrés' },
          { ic: 'edit', l: 'Vitrine publique', s: 'tropicalfoods.marche.cm' },
        ]}/>

        <MenuGroup title="Finances" items={[
          { ic: 'wallet', l: 'Revenus & retraits', s: '8,4 M disponibles', onClick: () => nav('v-earnings') },
          { ic: 'trending', l: 'Statistiques', s: '+18 % vs avril', onClick: () => nav('v-stats') },
          { ic: 'lock', l: 'PIN & sécurité', s: 'PIN actif · 2FA' },
        ]}/>

        <button onClick={onSwitchRole} style={{
          width: '100%', marginTop: 8, padding: 14, borderRadius: 14,
          background: T.accent, color: '#1a0f00', border: 'none',
          fontWeight: 800, fontSize: 14, cursor: 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          <Icon name="refresh" size={16} strokeWidth={2.4}/> Basculer en mode Acheteur
        </button>

        <div style={{ textAlign: 'center', fontSize: 10.5, color: T.ink4, marginTop: 16, padding: 4 }}>
          Marché CM · espace vendeur v2.1
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Vendor bottom nav
// ─────────────────────────────────────────────────────────────
function VBottomNav({ active, onNavigate }) {
  const items = [
    { id: 'v-dashboard', icon: 'home', label: 'Accueil' },
    { id: 'v-products', icon: 'package', label: 'Produits' },
    { id: 'v-orders', icon: 'bag', label: 'Commandes', badge: 3 },
    { id: 'v-stats', icon: 'trending', label: 'Stats' },
    { id: 'v-profile', icon: 'user', label: 'Profil' },
  ];
  return (
    <div style={{
      background: T.surface, borderTop: `1px solid ${T.line2}`,
      padding: '6px 4px 8px', display: 'grid', gridTemplateColumns: 'repeat(5,1fr)',
      flexShrink: 0,
    }}>
      {items.map(it => {
        const isActive = active === it.id;
        return (
          <button key={it.id} onClick={() => onNavigate?.(it.id)} style={{
            background: 'none', border: 'none', cursor: 'pointer',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            padding: '8px 4px', borderRadius: 10,
            color: isActive ? T.primary : T.ink3,
            minHeight: 56,
          }}>
            <div style={{
              padding: '4px 14px',
              background: isActive ? T.primarySoft : 'transparent',
              borderRadius: 999, position: 'relative',
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
            <span style={{ fontSize: 10.5, fontWeight: 600, color: isActive ? T.primary : T.ink3 }}>{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

Object.assign(window, {
  VDashboardScreen, VProductsScreen, VProductEditScreen,
  VOrdersScreen, VOrderDetailScreen, VEarningsScreen,
  VStatsScreen, VRfqScreen, VProfileScreen, VBottomNav,
  KpiCard, Alert, QuickAction, StepRow, MiniChart, Donut, SelectField, ToggleRow,
});
