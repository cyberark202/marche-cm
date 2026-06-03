/*
 * Marché CM — Livreur (Transitaire) screens
 * 9 écrans : Dashboard, Demandes ouvertes, Envoyer devis,
 *            Mes courses, Détail expédition, Preuve de livraison,
 *            Gains, Avis, Profil (Individuel ↔ Entreprise)
 *
 * Le rôle "Transitaire" du README couvre :
 *  - propose des devis
 *  - gère les expéditions et statuts
 *  - preuves de livraison (photo + code)
 *  - litiges
 *  - notation
 *  - profil transport
 *  - reçoit 5 % du montant de la commande via escrow
 */

// ─────────────────────────────────────────────────────────────
// L-1) DASHBOARD
// ─────────────────────────────────────────────────────────────
function LDashboardScreen({ nav, profileType }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg, paddingBottom: 16 }}>
      {/* Header amber — action-oriented */}
      <div style={{
        background: `linear-gradient(150deg, #C68426 0%, #8E5A00 100%)`,
        padding: '12px 16px 32px',
        borderRadius: '0 0 28px 28px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="truck" size={160} style={{ position: 'absolute', right: -30, bottom: -40, opacity: .08, color: '#fff' }}/>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <Avatar name="Eric Mballa" size={42} variant="accent" light/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11.5, opacity: .85, fontWeight: 600 }}>{profileType === 'company' ? 'Entreprise de livraison' : 'Livreur indépendant'}</div>
            <div style={{ fontSize: 15, fontWeight: 700, fontFamily: T.fontDisplay, display: 'flex', alignItems: 'center', gap: 6 }}>
              {profileType === 'company' ? 'Express Logistics SARL' : 'Eric Mballa'}
              <Pill variant="dark" size="sm">★ 4,8</Pill>
            </div>
          </div>
          <IconBtn name="bell" light badge={5} style={{ background: 'rgba(255,255,255,.15)', border: '1px solid rgba(255,255,255,.2)' }}/>
        </div>

        {/* Online toggle */}
        <div style={{
          marginTop: 16, padding: '10px 14px',
          background: 'rgba(255,255,255,.12)', borderRadius: 14,
          display: 'flex', alignItems: 'center', gap: 12,
          border: '1px solid rgba(255,255,255,.18)',
        }}>
          <span style={{ width: 12, height: 12, background: '#34D399', borderRadius: '50%', boxShadow: '0 0 0 4px rgba(52,211,153,.3)' }}/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>En ligne · accepte les courses</div>
            <div style={{ fontSize: 11, opacity: .8, marginTop: 1 }}>{profileType === 'company' ? '6 véhicules disponibles' : 'Toyota Hiace · Douala-centre'}</div>
          </div>
          <span style={{
            width: 44, height: 26, borderRadius: 999, background: T.success,
            position: 'relative', flexShrink: 0,
          }}>
            <span style={{ position: 'absolute', top: 3, right: 3, width: 20, height: 20, background: '#fff', borderRadius: '50%' }}/>
          </span>
        </div>

        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11, opacity: .75, fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase' }}>Gains · aujourd'hui</div>
          <div style={{ fontSize: 32, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 2 }}>
            42 500<span style={{ fontSize: 14, opacity: .7, fontWeight: 600, marginLeft: 6 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .85, marginTop: 3, display: 'flex', alignItems: 'center', gap: 6 }}>
            <Icon name="check" size={12} strokeWidth={3}/> 4 courses livrées · 2 en cours
          </div>
        </div>
      </div>

      {/* KPI grid */}
      <div style={{ padding: '0 16px', marginTop: -18, position: 'relative' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <KpiCard ic="scale" tone="warn" v="12" label="Devis ouverts" sub="à proposer" actionLabel="Voir" onAction={() => nav('l-bids')}/>
          <KpiCard ic="truck" tone="info" v="2" label="En cours" sub="Edéa · Kribi" actionLabel="Carte" onAction={() => nav('l-shipments')}/>
          <KpiCard ic="package" tone="success" v="148" label="Livrées" sub="ce mois"/>
          <KpiCard ic="trophy" tone="coral" v="98 %" label="À l'heure" sub="taux"/>
        </div>
      </div>

      {/* Hot bids strip */}
      <Section title="Demandes près de vous" action="Tout voir" onAction={() => nav('l-bids')}>
        <div style={{ display: 'flex', gap: 10, overflowX: 'auto', padding: '0 16px 4px', scrollbarWidth: 'none' }}>
          {[
            { from: 'Douala', to: 'Yaoundé', dist: '245 km', weight: '2,4 T', value: '2 320 000', kind: 'Huile palme × 200', urgent: true, bids: 3 },
            { from: 'Douala', to: 'Bafoussam', dist: '290 km', weight: '0,8 T', value: '648 000', kind: 'Ciment × 100', bids: 7 },
            { from: 'Douala', to: 'Kribi', dist: '170 km', weight: '0,5 T', value: '336 000', kind: 'Carton huile', bids: 2 },
          ].map((b, i) => (
            <button key={i} onClick={() => nav('l-quote')} style={{
              flexShrink: 0, width: 230,
              background: T.surface, border: `1px solid ${b.urgent ? T.accent : T.line}`,
              borderRadius: 14, padding: 12, cursor: 'pointer', textAlign: 'left',
              boxShadow: b.urgent ? `0 0 0 3px ${T.accentSoft}` : 'none',
            }}>
              {b.urgent && <Pill variant="accent" size="sm">URGENT</Pill>}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: b.urgent ? 8 : 0 }}>
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: T.primary }}/>
                <span style={{ fontSize: 13, fontWeight: 700 }}>{b.from}</span>
                <Icon name="arrowRight" size={14} color={T.ink3}/>
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: T.accent }}/>
                <span style={{ fontSize: 13, fontWeight: 700 }}>{b.to}</span>
              </div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 6, display: 'flex', alignItems: 'center', gap: 8 }}>
                <span>{b.dist}</span>
                <span style={{ width: 3, height: 3, background: T.ink4, borderRadius: 2 }}/>
                <span>{b.weight}</span>
                <span style={{ width: 3, height: 3, background: T.ink4, borderRadius: 2 }}/>
                <span>{b.bids} devis</span>
              </div>
              <div style={{ marginTop: 8, padding: '6px 8px', background: T.surface2, borderRadius: 8, fontSize: 11.5, color: T.ink2 }}>
                {b.kind} · <b style={{ color: T.ink, fontFeatureSettings: '"tnum"' }}>{b.value} FCFA</b>
              </div>
            </button>
          ))}
        </div>
      </Section>

      {/* Active shipments */}
      <Section title="Courses en cours" action="Toutes" onAction={() => nav('l-shipments')}>
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          {[
            { id: '#84F2E1B', from: 'Douala', to: 'Yaoundé', kind: 'Huile palme × 200', buyer: 'Awa Kamga', step: 'En route', stepPct: 65, eta: '18 mai', commission: '85 000', tone: 'warn' },
            { id: '#5DC182A', from: 'Douala', to: 'Kribi', kind: 'Carton huile × 30', buyer: 'Hôtel Akwa Palace', step: 'Pris en charge', stepPct: 25, eta: '15 mai', commission: '38 000', tone: 'info' },
          ].map((s, i) => (
            <button key={i} onClick={() => nav('l-shipment-detail')} style={{
              width: '100%', background: T.surface, border: `1px solid ${T.line}`,
              borderRadius: 16, padding: 14, cursor: 'pointer', textAlign: 'left',
              display: 'flex', flexDirection: 'column', gap: 10,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Pill variant={s.tone} size="sm">
                  <Icon name="truck" size={10} color={s.tone === 'warn' ? '#8E5A00' : '#3730A3'}/>
                  {s.step}
                </Pill>
                <span style={{ marginLeft: 'auto', fontSize: 10, color: T.ink3, fontFamily: T.fontMono }}>{s.id}</span>
              </div>
              {/* Route */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 14 }}>
                <div style={{ width: 10, height: 10, borderRadius: '50%', background: T.primary, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + T.primary }}/>
                <span style={{ fontWeight: 700 }}>{s.from}</span>
                <div style={{ flex: 1, height: 2, background: `linear-gradient(to right, ${T.primary} 0%, ${T.primary} ${s.stepPct}%, ${T.line} ${s.stepPct}%, ${T.line} 100%)`, borderRadius: 1, position: 'relative' }}>
                  <span style={{
                    position: 'absolute', top: -10, left: `${s.stepPct}%`, transform: 'translateX(-50%)',
                    width: 22, height: 22, borderRadius: '50%', background: T.accent,
                    display: 'grid', placeItems: 'center', color: '#1a0f00',
                  }}>
                    <Icon name="truck" size={12}/>
                  </span>
                </div>
                <span style={{ fontWeight: 700 }}>{s.to}</span>
                <div style={{ width: 10, height: 10, borderRadius: '50%', background: T.line, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + T.line }}/>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: 11.5, color: T.ink3 }}>
                <span>{s.kind} · {s.buyer}</span>
                <span style={{ color: T.success, fontWeight: 700, fontFeatureSettings: '"tnum"' }}>+ {s.commission} FCFA</span>
              </div>
            </button>
          ))}
        </div>
      </Section>

      {/* Weekly mini perf */}
      <Section title="Performance · cette semaine">
        <div style={{ padding: '0 16px' }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14 }}>
            <MiniChart values={[0.35, 0.48, 0.55, 0.42, 0.7, 0.85, 1.0]} labels={['L','M','M','J','V','S','D']}/>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 12 }}>
              <div>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Gains semaine</div>
                <div style={{ fontSize: 22, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>284 000 <span style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>FCFA</span></div>
              </div>
              <Pill variant="success"><Icon name="trending" size={11} color={T.primaryDark} strokeWidth={3}/>+15 %</Pill>
            </div>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-2) BIDS — open shipment requests to bid on
// ─────────────────────────────────────────────────────────────
function LBidsScreen({ nav }) {
  const [filter, setFilter] = React.useState('Tous');
  const bids = [
    { from: 'Douala', to: 'Yaoundé', dist: '245 km', weight: '2,4 T', kind: 'Huile palme × 200', value: '2 320 000', urgent: true, bids: 3, supplier: 'Tropical Foods', estimate: '85 000', deadline: '6 h' },
    { from: 'Douala', to: 'Bafoussam', dist: '290 km', weight: '0,8 T', kind: 'Ciment × 100', value: '648 000', bids: 7, supplier: 'BTP Cameroun', estimate: '62 000', deadline: '24 h' },
    { from: 'Douala', to: 'Kribi', dist: '170 km', weight: '0,5 T', kind: 'Carton huile × 30', value: '336 000', bids: 2, supplier: 'Tropical Foods', estimate: '38 000', deadline: '12 h' },
    { from: 'Yaoundé', to: 'Bertoua', dist: '350 km', weight: '1,2 T', kind: 'Sacs riz × 40', value: '1 140 000', bids: 5, supplier: 'Yaoundé Foods', estimate: '95 000', deadline: '48 h' },
    { from: 'Douala', to: 'Limbé', dist: '70 km', weight: '0,2 T', kind: 'Cacao × 4 sacs', value: '168 000', bids: 1, supplier: 'AfricaTrade', estimate: '18 000', deadline: '3 h', urgent: true },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Demandes ouvertes" subtitle={`${bids.length} expéditions à pourvoir`} right={<><IconBtn name="filter"/><IconBtn name="sort"/></>}/>

      {/* Filter chips */}
      <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '0 16px 12px', scrollbarWidth: 'none' }}>
        {['Tous', 'Proches', '< 100 km', '100-300 km', 'Express', 'Urgent', 'Gros volume'].map(c => (
          <button key={c} onClick={() => setFilter(c)} style={{
            flexShrink: 0, padding: '7px 14px', borderRadius: 999,
            background: filter === c ? T.ink : T.surface,
            color: filter === c ? '#fff' : T.ink2,
            border: `1px solid ${filter === c ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 700, cursor: 'pointer',
            whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {bids.map((b, i) => (
          <button key={i} onClick={() => nav('l-quote')} style={{
            width: '100%', background: T.surface,
            border: `1px solid ${b.urgent ? T.accent : T.line}`,
            borderRadius: 16, padding: 14, cursor: 'pointer', textAlign: 'left',
            boxShadow: b.urgent ? `0 0 0 3px ${T.accentSoft}` : 'none',
          }}>
            {/* Top : urgency + deadline */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
              {b.urgent ? <Pill variant="accent" size="sm">URGENT · {b.deadline}</Pill> : <Pill variant="neutral" size="sm">{b.deadline}</Pill>}
              <Pill variant="info" size="sm"><Icon name="user" size={10} color="#3730A3"/>{b.bids} devis</Pill>
              <span style={{ marginLeft: 'auto', fontSize: 11, color: T.ink3 }}>{b.supplier}</span>
            </div>

            {/* Route visualization */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
                <div style={{ width: 12, height: 12, borderRadius: '50%', background: T.primary, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + T.primary }}/>
                <div style={{ width: 2, flex: 1, background: `repeating-linear-gradient(to bottom, ${T.line2} 0, ${T.line2} 4px, transparent 4px, transparent 8px)`, minHeight: 18 }}/>
                <div style={{ width: 12, height: 12, borderRadius: '50%', background: T.accent, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + T.accent }}/>
              </div>
              <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 10 }}>
                <div>
                  <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Enlèvement</div>
                  <div style={{ fontSize: 14, fontWeight: 700 }}>{b.from}</div>
                </div>
                <div>
                  <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Livraison</div>
                  <div style={{ fontSize: 14, fontWeight: 700 }}>{b.to}</div>
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Distance</div>
                <div style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{b.dist}</div>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600, marginTop: 6 }}>Poids</div>
                <div style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{b.weight}</div>
              </div>
            </div>

            {/* Cargo + estimate */}
            <div style={{ marginTop: 10, padding: '10px 12px', background: T.surface2, borderRadius: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="package" size={14} color={T.ink3}/>
              <span style={{ flex: 1, fontSize: 12, color: T.ink2, fontWeight: 600 }}>{b.kind}</span>
              <span style={{ fontSize: 11, color: T.ink3 }}>val. {b.value} F</span>
            </div>

            {/* Estimate + CTA */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 }}>
              <div>
                <div style={{ fontSize: 10.5, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>Tarif moyen</div>
                <div style={{ fontSize: 16, fontWeight: 800, fontFeatureSettings: '"tnum"', color: T.primary }}>{b.estimate} <span style={{ fontSize: 10, color: T.ink3, fontWeight: 600 }}>FCFA</span></div>
              </div>
              <Btn variant="primary" size="sm" iconRight="arrowRight">Devis</Btn>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-3) QUOTE — submit a quote
// ─────────────────────────────────────────────────────────────
function LQuoteScreen({ nav }) {
  const [price, setPrice] = React.useState('85000');
  const [eta, setEta] = React.useState(5);
  const [vehicle, setVehicle] = React.useState('hiace');
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('l-bids')} title="Envoyer un devis" subtitle="Douala → Yaoundé · 2,4 T"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {/* Shipment context */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14, marginBottom: 14,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <Pill variant="accent" size="sm">URGENT · 6 h</Pill>
            <Pill variant="info" size="sm">3 devis déjà soumis</Pill>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14 }}>
            <span style={{ fontWeight: 700 }}>Douala</span>
            <Icon name="arrowRight" size={14} color={T.ink3}/>
            <span style={{ fontWeight: 700 }}>Yaoundé</span>
            <span style={{ marginLeft: 'auto', fontSize: 11, color: T.ink3 }}>245 km · 2,4 T</span>
          </div>
          <div style={{ padding: '8px 10px', background: T.surface2, borderRadius: 10, marginTop: 8, fontSize: 12, color: T.ink2 }}>
            <Icon name="package" size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 5 }}/> Huile palme 20 L × 200 · val. 2 320 000 F · Tropical Foods
          </div>
        </div>

        {/* Vehicle */}
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Véhicule</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
            {[
              { id: 'moto', icon: 'truck', name: 'Moto', sub: '< 50 kg' },
              { id: 'hiace', icon: 'truck', name: 'Toyota Hiace', sub: '< 3 T' },
              { id: 'camion', icon: 'truck', name: 'Camion 10 T', sub: 'lourd' },
            ].map(v => {
              const active = vehicle === v.id;
              return (
                <button key={v.id} onClick={() => setVehicle(v.id)} style={{
                  padding: 10, borderRadius: 12, cursor: 'pointer',
                  background: active ? T.primarySoft : T.surface,
                  border: `1.5px solid ${active ? T.primary : T.line}`,
                  boxShadow: active ? `0 0 0 3px ${T.primarySoft}` : 'none',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                }}>
                  <Icon name={v.icon} size={22} color={active ? T.primary : T.ink2}/>
                  <div style={{ fontSize: 12, fontWeight: 700, color: active ? T.primary : T.ink, marginTop: 2 }}>{v.name}</div>
                  <div style={{ fontSize: 10, color: T.ink3 }}>{v.sub}</div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Price */}
        <div style={{
          background: `linear-gradient(135deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          borderRadius: 18, padding: 18, color: '#fff', position: 'relative', overflow: 'hidden',
        }}>
          <Icon name="wallet" size={120} style={{ position: 'absolute', right: -20, top: -20, opacity: .08 }}/>
          <div style={{ fontSize: 11, opacity: .7, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Votre prix proposé</div>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', marginTop: 8, gap: 6 }}>
            <input
              value={parseInt(price || '0', 10).toLocaleString('fr-FR')}
              onChange={e => setPrice(e.target.value.replace(/\D/g, ''))}
              style={{
                background: 'transparent', border: 'none', outline: 'none', color: '#fff',
                fontSize: 38, fontWeight: 800, width: 200, textAlign: 'right',
                fontFamily: T.fontDisplay, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em',
              }}
            />
            <span style={{ fontSize: 13, opacity: .8, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .85, marginTop: 6, textAlign: 'center' }}>
            Tarif moyen sur cette route : 82 000 F · 3 devis entre 78 k et 95 k
          </div>
        </div>

        {/* ETA */}
        <div style={{
          marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
            <span style={{ fontSize: 12.5, fontWeight: 700, color: T.ink2 }}>Délai de livraison</span>
            <span style={{ fontSize: 16, fontWeight: 800, color: T.ink, fontFeatureSettings: '"tnum"' }}>{eta} jour{eta > 1 ? 's' : ''}</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <button onClick={() => setEta(Math.max(1, eta - 1))} style={{
              width: 38, height: 38, borderRadius: 10, border: 'none',
              background: T.surface2, cursor: 'pointer',
              display: 'grid', placeItems: 'center',
            }}><Icon name="minus" size={14} color={T.ink2} strokeWidth={2.5}/></button>
            <div style={{ flex: 1, height: 6, background: T.surface2, borderRadius: 3, position: 'relative' }}>
              <div style={{ position: 'absolute', left: 0, top: 0, width: `${(eta/14)*100}%`, height: '100%', background: T.primary, borderRadius: 3 }}/>
              <span style={{ position: 'absolute', left: `${(eta/14)*100}%`, top: '50%', transform: 'translate(-50%, -50%)', width: 16, height: 16, background: T.surface, border: `3px solid ${T.primary}`, borderRadius: '50%' }}/>
            </div>
            <button onClick={() => setEta(Math.min(14, eta + 1))} style={{
              width: 38, height: 38, borderRadius: 10, border: 'none',
              background: T.surface2, cursor: 'pointer',
              display: 'grid', placeItems: 'center',
            }}><Icon name="plus" size={14} color={T.ink2} strokeWidth={2.5}/></button>
          </div>
        </div>

        {/* Options */}
        <div style={{ marginTop: 14, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12 }}>
          <ToggleRow icon="shieldCheck" label="Assurance incluse" sub="Couvre la valeur marchandise" on/>
          <div style={{ height: 1, background: T.line2, margin: '4px 0' }}/>
          <ToggleRow icon="package" label="Manutention chargement" sub="Aide à la mise en charge" on/>
          <div style={{ height: 1, background: T.line2, margin: '4px 0' }}/>
          <ToggleRow icon="clock" label="Livraison express +50 %" sub="Garantie en 2 jours" on={false}/>
        </div>

        {/* Earnings preview */}
        <div style={{
          marginTop: 14, padding: 12, background: T.primarySoft, borderRadius: 12,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <Icon name="trending" size={18} color={T.primary}/>
          <div style={{ flex: 1, fontSize: 12, color: T.primaryDark }}>
            Si accepté, vous recevez <b style={{ fontFeatureSettings: '"tnum"' }}>80 750 FCFA</b> (95 %) après preuve de livraison.
          </div>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '10px 14px', display: 'flex', gap: 8, flexShrink: 0 }}>
        <Btn variant="outline" size="md" style={{ flex: 1 }} onClick={() => nav('l-bids')}>Annuler</Btn>
        <Btn variant="primary" size="md" icon="send" style={{ flex: 2 }} onClick={() => nav('l-shipments')}>Envoyer le devis</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-4) SHIPMENTS — my courses
// ─────────────────────────────────────────────────────────────
function LShipmentsScreen({ nav }) {
  const [tab, setTab] = React.useState('cours');
  const tabs = [
    { id: 'devis', label: 'Devis envoyés', count: 4 },
    { id: 'cours', label: 'En cours', count: 2 },
    { id: 'livre', label: 'Livrées', count: 148 },
  ];
  const data = {
    devis: [
      { id: '#9F2C8E1', from: 'Yaoundé', to: 'Bafoussam', kind: 'Cacao 4 sacs', price: '32 000', state: 'En attente', tone: 'neutral' },
      { id: '#A172DF3', from: 'Douala', to: 'Edéa', kind: 'Bidons huile × 50', price: '24 000', state: 'En attente', tone: 'neutral' },
    ],
    cours: [
      { id: '#84F2E1B', from: 'Douala', to: 'Yaoundé', kind: 'Huile palme × 200', buyer: 'Awa Kamga', step: 'En route', pct: 65, eta: '18 mai', tone: 'warn' },
      { id: '#5DC182A', from: 'Douala', to: 'Kribi', kind: 'Carton huile × 30', buyer: 'Hôtel Akwa Palace', step: 'Pris en charge', pct: 25, eta: '15 mai', tone: 'info' },
    ],
    livre: [
      { id: '#71A09C0', from: 'Douala', to: 'Yaoundé', kind: 'Riz × 20 sacs', step: 'Livrée', pct: 100, paid: '+ 62 000', tone: 'success', date: 'il y a 3 j' },
      { id: '#4A1F081', from: 'Douala', to: 'Limbé', kind: 'Cacao × 6 sacs', step: 'Livrée', pct: 100, paid: '+ 18 000', tone: 'success', date: 'il y a 5 j' },
    ],
  };
  const list = data[tab] || [];

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Mes courses" subtitle="Devis · en cours · historique" right={<IconBtn name="filter"/>}/>

      {/* Tabs */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          display: 'flex', background: T.surface2, padding: 4, borderRadius: 12, gap: 2,
          border: `1px solid ${T.line2}`,
        }}>
          {tabs.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, padding: '8px 4px', border: 'none', cursor: 'pointer',
              background: tab === t.id ? T.surface : 'transparent',
              boxShadow: tab === t.id ? T.shadowSm : 'none',
              borderRadius: 9, fontSize: 12, fontWeight: 700,
              color: tab === t.id ? T.ink : T.ink2,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 5,
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

      {/* List */}
      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {list.map((s, i) => (
          <button key={i} onClick={() => nav('l-shipment-detail')} style={{
            width: '100%', background: T.surface, border: `1px solid ${T.line}`,
            borderRadius: 16, padding: 14, cursor: 'pointer', textAlign: 'left',
            display: 'flex', flexDirection: 'column', gap: 10,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Pill variant={s.tone} size="sm">
                {s.tone === 'success' && <Icon name="check" size={10} color={T.primaryDark} strokeWidth={3}/>}
                {s.tone === 'warn' && <Icon name="truck" size={10} color="#8E5A00"/>}
                {s.tone === 'info' && <Icon name="package" size={10} color="#3730A3"/>}
                {s.step}
              </Pill>
              {s.date && <span style={{ fontSize: 11, color: T.ink3 }}>{s.date}</span>}
              <span style={{ marginLeft: 'auto', fontSize: 10, color: T.ink3, fontFamily: T.fontMono }}>{s.id}</span>
            </div>

            {/* Route */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 14 }}>
              <div style={{ width: 10, height: 10, borderRadius: '50%', background: T.primary, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + T.primary }}/>
              <span style={{ fontWeight: 700 }}>{s.from}</span>
              <div style={{ flex: 1, height: 2, background: `linear-gradient(to right, ${T.primary} 0%, ${T.primary} ${s.pct || 0}%, ${T.line} ${s.pct || 0}%, ${T.line} 100%)`, borderRadius: 1 }}/>
              <span style={{ fontWeight: 700 }}>{s.to}</span>
              <div style={{ width: 10, height: 10, borderRadius: '50%', background: (s.pct === 100) ? T.primary : T.line, border: '2.5px solid white', boxShadow: '0 0 0 1px ' + ((s.pct === 100) ? T.primary : T.line) }}/>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: 11.5, color: T.ink3 }}>
              <span>{s.kind}{s.buyer ? ` · ${s.buyer}` : ''}{s.eta ? ` · ETA ${s.eta}` : ''}</span>
              <span style={{
                color: s.tone === 'success' ? T.success : T.ink2,
                fontWeight: 700, fontFeatureSettings: '"tnum"',
              }}>{s.paid || (s.price ? `${s.price} FCFA` : '')}</span>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-5) SHIPMENT DETAIL — map + status updates + proof
// ─────────────────────────────────────────────────────────────
function LShipmentDetailScreen({ nav }) {
  const [stage, setStage] = React.useState(2);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      {/* Map hero */}
      <div style={{ position: 'relative' }}>
        <MapBg/>
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, padding: '8px 16px', display: 'flex', alignItems: 'center', gap: 10, justifyContent: 'space-between' }}>
          <IconBtn name="arrowLeft" onClick={() => nav('l-shipments')} style={{
            background: 'rgba(255,255,255,.92)', border: 'none', boxShadow: T.shadowSm,
          }}/>
          <div style={{ display: 'flex', gap: 8 }}>
            <IconBtn name="phone" style={{ background: 'rgba(255,255,255,.92)', boxShadow: T.shadowSm }}/>
            <IconBtn name="chat" onClick={() => nav('chat-thread')} style={{ background: 'rgba(255,255,255,.92)', boxShadow: T.shadowSm }}/>
            <IconBtn name="moreV" style={{ background: 'rgba(255,255,255,.92)', boxShadow: T.shadowSm }}/>
          </div>
        </div>

        {/* ETA chip */}
        <div style={{
          position: 'absolute', bottom: 12, left: 14, right: 14,
          background: 'rgba(255,255,255,.96)', borderRadius: 14, padding: '10px 14px',
          display: 'flex', alignItems: 'center', gap: 12,
          boxShadow: T.shadowMd,
        }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, background: T.accent, color: '#1a0f00', display: 'grid', placeItems: 'center' }}>
            <Icon name="truck" size={20}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Arrivée estimée</div>
            <div style={{ fontSize: 16, fontWeight: 800, fontFamily: T.fontDisplay, letterSpacing: '-0.01em' }}>lundi 18 mai · 14:30</div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Position</div>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Edéa</div>
          </div>
        </div>
      </div>

      {/* Sheet */}
      <div style={{
        flex: 1, background: T.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28,
        marginTop: -20, padding: '18px 16px 100px', overflow: 'auto',
        position: 'relative', zIndex: 1,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
          <span style={{ fontSize: 10, color: T.ink3, fontFamily: T.fontMono, letterSpacing: '.04em' }}>CMD #84F2E1B</span>
          <Pill variant="warn" size="sm">EN TRANSIT</Pill>
        </div>

        {/* Cargo */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12,
          display: 'flex', gap: 12, alignItems: 'center',
        }}>
          <Ph icon="package" height={52} radius={9} tone="accent"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Huile palme 20 L × 200</div>
            <div style={{ fontSize: 11, color: T.ink3, marginTop: 2 }}>2,4 T · valeur 2 320 000 F</div>
          </div>
        </div>

        {/* Parties */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginTop: 8 }}>
          <PartyCard role="Expéditeur" name="Tropical Foods" loc="Douala" av="TF" variant="primary"/>
          <PartyCard role="Destinataire" name="Awa Kamga" loc="Yaoundé" av="AK" variant="info"/>
        </div>

        {/* Earnings */}
        <div style={{
          marginTop: 12, padding: 14, background: T.primarySoft, borderRadius: 14,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <div style={{ width: 38, height: 38, borderRadius: 10, background: T.primary, color: '#fff', display: 'grid', placeItems: 'center' }}>
            <Icon name="wallet" size={18}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11.5, fontWeight: 700, color: T.primaryDark, textTransform: 'uppercase', letterSpacing: '.04em' }}>Votre gain</div>
            <div style={{ fontSize: 18, fontWeight: 800, color: T.primaryDark, fontFeatureSettings: '"tnum"' }}>80 750 <span style={{ fontSize: 11, fontWeight: 600 }}>FCFA · à libérer après preuve</span></div>
          </div>
        </div>

        {/* Stages */}
        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Étapes de la course</div>
          <StepRow done idx={1} title="Devis accepté" sub="12 mai · 10:18"/>
          <StepRow done idx={2} title="Colis pris en charge" sub="13 mai · 07:30 · Entrepôt Douala"/>
          <StepRow done={stage > 2} active={stage === 2} idx={3}
            title="En route vers Yaoundé"
            sub="Position : Edéa · ETA 14:30"
            cta={stage === 2 ? "Mettre à jour position" : null}
            onCta={() => setStage(3)}/>
          <StepRow done={stage > 3} active={stage === 3} idx={4}
            title="Arrivée chez l'acheteur"
            sub="Notifier Awa Kamga"
            cta={stage === 3 ? "Marquer arrivé" : null}
            onCta={() => setStage(4)}/>
          <StepRow active={stage === 4} idx={5}
            title="Preuve de livraison"
            sub="Photo + code à 4 chiffres"
            cta={stage === 4 ? "Capturer la preuve" : null}
            onCta={() => nav('l-proof')}/>
          <StepRow idx={6} title="Libération du paiement" sub="80 750 FCFA → votre wallet" final/>
        </div>
      </div>
    </div>
  );
}

function MapBg() {
  // Stylized SVG map background
  return (
    <div style={{
      height: 230, position: 'relative', overflow: 'hidden',
      background: `linear-gradient(135deg, #E6F2EC 0%, #F1ECDE 100%)`,
    }}>
      <svg width="100%" height="100%" viewBox="0 0 400 230" style={{ position: 'absolute', inset: 0 }}>
        {/* roads */}
        <path d="M -20 180 Q 80 160 150 140 T 320 80 T 420 60" stroke="#E5DECC" strokeWidth="18" fill="none" strokeLinecap="round"/>
        <path d="M -20 180 Q 80 160 150 140 T 320 80 T 420 60" stroke="#F1ECDE" strokeWidth="14" fill="none" strokeLinecap="round" strokeDasharray="2 6"/>
        <path d="M 50 220 L 100 180 L 160 200 L 220 170 L 280 190" stroke="#E5DECC" strokeWidth="6" fill="none" strokeLinecap="round" opacity=".5"/>
        {/* small buildings */}
        {[
          [40, 80, 14, 10], [62, 78, 10, 12], [80, 82, 12, 8],
          [300, 50, 14, 12], [322, 45, 10, 15], [340, 52, 12, 10],
          [180, 120, 8, 8], [200, 116, 10, 10], [220, 122, 8, 8],
        ].map((b, i) => (
          <rect key={i} x={b[0]} y={b[1]} width={b[2]} height={b[3]} fill="#D8D0BC" rx="1.5"/>
        ))}
        {/* trees */}
        {[[120, 100], [250, 130], [350, 100], [70, 200]].map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r="4" fill="#A8C5B0" opacity=".7"/>
        ))}
        {/* origin */}
        <circle cx="55" cy="178" r="8" fill="#0F7A4F"/>
        <circle cx="55" cy="178" r="3" fill="#fff"/>
        {/* destination */}
        <circle cx="345" cy="68" r="8" fill="#F5B400"/>
        <circle cx="345" cy="68" r="3" fill="#fff"/>
        {/* truck (current position) */}
        <g transform="translate(195 110) rotate(-20)">
          <rect x="-10" y="-7" width="20" height="14" rx="2" fill="#0E1F18"/>
          <rect x="-9" y="-6" width="18" height="6" fill="#fff" opacity=".4"/>
          <circle cx="-5" cy="9" r="3" fill="#0E1F18"/>
          <circle cx="6" cy="9" r="3" fill="#0E1F18"/>
        </g>
        {/* pulse ring */}
        <circle cx="195" cy="110" r="20" fill="none" stroke="#F5B400" strokeWidth="2" opacity=".5">
          <animate attributeName="r" from="14" to="28" dur="1.6s" repeatCount="indefinite"/>
          <animate attributeName="opacity" from=".6" to="0" dur="1.6s" repeatCount="indefinite"/>
        </circle>
        {/* labels */}
        <text x="50" y="170" fontSize="11" fontFamily="'Plus Jakarta Sans'" fontWeight="700" fill="#0F7A4F">Douala</text>
        <text x="320" y="60" fontSize="11" fontFamily="'Plus Jakarta Sans'" fontWeight="700" fill="#8E5A00">Yaoundé</text>
        <text x="170" y="105" fontSize="9" fontFamily="'Plus Jakarta Sans'" fontWeight="600" fill="#3A4A44">Edéa</text>
      </svg>
    </div>
  );
}

function PartyCard({ role, name, loc, av, variant }) {
  return (
    <div style={{
      background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10,
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <Avatar name={name} size={34} variant={variant}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 10, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>{role}</div>
        <div style={{ fontSize: 12.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ fontSize: 10.5, color: T.ink3, display: 'flex', alignItems: 'center', gap: 3, marginTop: 1 }}>
          <Icon name="mapPin" size={10}/> {loc}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-6) PROOF OF DELIVERY — photo + 4-digit code
// ─────────────────────────────────────────────────────────────
function LProofScreen({ nav }) {
  const [code, setCode] = React.useState(['', '', '', '']);
  const [captured, setCaptured] = React.useState(false);

  const updateDigit = (i, v) => {
    if (!/^\d?$/.test(v)) return;
    const next = [...code];
    next[i] = v;
    setCode(next);
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('l-shipment-detail')} title="Preuve de livraison" subtitle="CMD #84F2E1B"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {/* Photo capture zone */}
        <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>1 · Photo du colis livré</div>
        <button onClick={() => setCaptured(!captured)} style={{
          width: '100%', height: 220, borderRadius: 18, border: 'none', cursor: 'pointer',
          background: captured ? `linear-gradient(135deg, ${T.primarySoft}, #D9EADF)` : T.surface,
          ...(captured ? {} : { border: `2px dashed ${T.line}` }),
          display: 'grid', placeItems: 'center', position: 'relative', overflow: 'hidden',
        }}>
          {captured ? (
            <>
              <Ph icon="package" height={220} radius={0} tone="primary"/>
              <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.3)', display: 'grid', placeItems: 'center' }}>
                <div style={{ background: '#fff', padding: '8px 14px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12.5, fontWeight: 700, color: T.primaryDark }}>
                  <Icon name="checkCircle" size={16} color={T.primary}/> Photo capturée · re-prendre
                </div>
              </div>
            </>
          ) : (
            <div style={{ textAlign: 'center' }}>
              <div style={{ width: 70, height: 70, borderRadius: '50%', background: T.surface2, color: T.ink3, display: 'grid', placeItems: 'center', margin: '0 auto' }}>
                <Icon name="camera" size={32} strokeWidth={1.6}/>
              </div>
              <div style={{ fontSize: 14, fontWeight: 700, marginTop: 10, color: T.ink }}>Prendre la photo</div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 4 }}>Bidons devant la porte du destinataire</div>
            </div>
          )}
        </button>

        {/* Code entry */}
        <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginTop: 22, marginBottom: 8 }}>2 · Code de confirmation acheteur</div>
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16,
        }}>
          <div style={{ fontSize: 12.5, color: T.ink2, lineHeight: 1.5 }}>
            Demandez à <b style={{ color: T.ink }}>Awa Kamga</b> son <b>code à 4 chiffres</b> reçu par SMS. Tapez-le ci-dessous.
          </div>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'center', marginTop: 16 }}>
            {code.map((d, i) => (
              <input key={i} value={d} maxLength={1}
                onChange={e => updateDigit(i, e.target.value)}
                style={{
                  width: 56, height: 66, textAlign: 'center',
                  fontSize: 30, fontWeight: 800, fontFamily: T.fontDisplay,
                  background: T.bg, border: `1.5px solid ${d ? T.primary : T.line}`,
                  borderRadius: 14, color: T.ink, outline: 'none',
                  boxShadow: d ? `0 0 0 3px ${T.primarySoft}` : 'none',
                  transition: `border-color ${T.duration} ${T.ease}`,
                  fontFeatureSettings: '"tnum"',
                }}/>
            ))}
          </div>
          <button style={{
            marginTop: 12, background: 'none', border: 'none', cursor: 'pointer',
            color: T.primary, fontSize: 12.5, fontWeight: 700, padding: '6px 12px',
            display: 'block', margin: '12px auto 0',
          }}>Renvoyer le code à l'acheteur</button>
        </div>

        {/* GPS confirmation */}
        <div style={{
          marginTop: 14, padding: 12, background: T.primarySoft, borderRadius: 12,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <Icon name="mapPin" size={18} color={T.primary}/>
          <div style={{ flex: 1, fontSize: 12, color: T.primaryDark, lineHeight: 1.4 }}>
            Position GPS confirmée à <b>Yaoundé · Bastos</b> · à 12 m de l'adresse de livraison.
          </div>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '10px 14px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full icon="checkCircle" onClick={() => nav('l-shipments')}>
          Valider la livraison
        </Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-7) EARNINGS (livreur)
// ─────────────────────────────────────────────────────────────
function LEarningsScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Gains" subtitle="Wallet livreur"/>

      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          background: `linear-gradient(140deg, #C68426 0%, #8E5A00 100%)`,
          borderRadius: 22, padding: 20, color: '#fff', position: 'relative', overflow: 'hidden',
          boxShadow: T.shadowAccent,
        }}>
          <Icon name="trophy" size={120} color="#fff" style={{ position: 'absolute', right: -25, top: -25, opacity: .1 }}/>
          <div style={{ fontSize: 11, opacity: .8, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Disponible</div>
          <div style={{ fontSize: 32, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 4 }}>
            384 200<span style={{ fontSize: 14, opacity: .7, marginLeft: 6, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ marginTop: 16, display: 'flex', gap: 8 }}>
            <Btn variant="dark" size="md" icon="arrowRight" style={{ flex: 1 }}>Retirer MoMo</Btn>
            <IconBtn name="refresh" light style={{ background: 'rgba(255,255,255,.15)', border: '1px solid rgba(255,255,255,.2)' }}/>
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px 14px' }}>
        <StatCard ic="shield" label="À libérer" value="160 750" sub="2 courses en cours" tone="info"/>
        <StatCard ic="trending" label="Ce mois" value="+ 1,42 M" sub="148 courses" tone="success"/>
      </div>

      {/* Weekly chart */}
      <Section title="Gains · 7 jours">
        <div style={{ padding: '0 16px' }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16 }}>
            <MiniChart values={[0.35, 0.48, 0.55, 0.42, 0.7, 0.85, 1.0]} labels={['L','M','M','J','V','S','D']}/>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 12 }}>
              <div>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Total semaine</div>
                <div style={{ fontSize: 22, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>284 000 <span style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>FCFA</span></div>
              </div>
              <Pill variant="success"><Icon name="trending" size={11} color={T.primaryDark} strokeWidth={3}/>+15 %</Pill>
            </div>
          </div>
        </div>
      </Section>

      {/* Released payments */}
      <Section title="Paiements libérés" action="Tout">
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, margin: '0 16px', overflow: 'hidden' }}>
          {[
            { route: 'Douala → Yaoundé', kind: 'Riz × 20 sacs', date: 'il y a 3 j', v: '+ 62 000' },
            { route: 'Douala → Limbé', kind: 'Cacao × 6 sacs', date: 'il y a 5 j', v: '+ 18 000' },
            { route: 'Yaoundé → Bafoussam', kind: 'Huile × 80 bidons', date: 'il y a 7 j', v: '+ 78 000' },
            { route: 'Douala → Edéa', kind: 'Ciment × 100', date: 'il y a 8 j', v: '+ 28 000' },
          ].map((tx, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10, background: T.primarySoft, color: T.primaryDark,
                display: 'grid', placeItems: 'center',
              }}><Icon name="truck" size={16}/></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: T.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.route}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{tx.kind} · {tx.date}</div>
              </div>
              <div style={{ fontSize: 13, fontWeight: 700, color: T.success, fontFeatureSettings: '"tnum"' }}>{tx.v}</div>
            </div>
          ))}
        </div>
      </Section>
      <div style={{ height: 16 }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-8) REVIEWS — buyer ratings
// ─────────────────────────────────────────────────────────────
function LReviewsScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader onBack={() => nav('l-profile')} title="Mes avis" subtitle="218 évaluations"/>

      {/* Big rating */}
      <div style={{ padding: '4px 16px 14px' }}>
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 18, padding: 18,
          display: 'flex', alignItems: 'center', gap: 16,
        }}>
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 44, fontWeight: 800, color: T.ink, letterSpacing: '-0.03em', lineHeight: 1, fontFeatureSettings: '"tnum"' }}>4,8</div>
            <Stars value={5} size={14}/>
            <div style={{ fontSize: 11, color: T.ink3, marginTop: 4 }}>218 avis</div>
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4 }}>
            {[
              { n: 5, pct: 78 },
              { n: 4, pct: 16 },
              { n: 3, pct: 4 },
              { n: 2, pct: 1 },
              { n: 1, pct: 1 },
            ].map(r => (
              <div key={r.n} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10.5 }}>
                <span style={{ width: 8, color: T.ink2, fontWeight: 700 }}>{r.n}</span>
                <Icon name="star" size={11} color={T.accent}/>
                <div style={{ flex: 1, height: 6, background: T.surface2, borderRadius: 3 }}>
                  <div style={{ width: `${r.pct}%`, height: '100%', background: T.accent, borderRadius: 3 }}/>
                </div>
                <span style={{ width: 30, textAlign: 'right', color: T.ink3, fontFeatureSettings: '"tnum"' }}>{r.pct} %</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Tag chips */}
      <div style={{ display: 'flex', gap: 6, padding: '0 16px 12px', flexWrap: 'wrap' }}>
        {[
          { l: 'Ponctuel', n: 156 },
          { l: 'Soigneux', n: 142 },
          { l: 'Aimable', n: 98 },
          { l: 'Bon emballage', n: 87 },
          { l: 'Communication +', n: 64 },
        ].map((t, i) => (
          <span key={i} style={{
            padding: '5px 10px', borderRadius: 999, background: T.primarySoft,
            color: T.primaryDark, fontSize: 11, fontWeight: 700,
            display: 'inline-flex', alignItems: 'center', gap: 4,
          }}>{t.l} <span style={{ background: T.surface, padding: '1px 6px', borderRadius: 999, fontSize: 10, fontFeatureSettings: '"tnum"' }}>{t.n}</span></span>
        ))}
      </div>

      {/* Reviews list */}
      <div style={{ padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {[
          { name: 'Awa Kamga', city: 'Yaoundé', stars: 5, time: 'il y a 2 j', text: "Livraison parfaite, à l'heure et marchandise intacte. Eric a même appelé pour confirmer le quartier. Je recommande !", tags: ['Ponctuel', 'Soigneux'] },
          { name: 'Hôtel Akwa Palace', city: 'Douala', stars: 5, time: 'il y a 4 j', text: 'Très bonne communication tout le long du transport. Express Logistics est notre transitaire de référence maintenant.', tags: ['Communication +'] },
          { name: 'Mama Ngozi', city: 'Bafoussam', stars: 4, time: 'il y a 1 sem', text: "Bon service mais arrivée avec 1 jour de retard à cause de la pluie. Le chauffeur s'est excusé.", tags: ['Aimable'] },
        ].map((r, i) => (
          <div key={i} style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Avatar name={r.name} size={36} variant="info"/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 700 }}>{r.name}</div>
                <div style={{ fontSize: 11, color: T.ink3, display: 'flex', alignItems: 'center', gap: 4, marginTop: 1 }}>
                  <Icon name="mapPin" size={10}/> {r.city} · {r.time}
                </div>
              </div>
              <Stars value={r.stars}/>
            </div>
            <div style={{ fontSize: 13, color: T.ink2, lineHeight: 1.5, marginTop: 10 }}>{r.text}</div>
            <div style={{ display: 'flex', gap: 4, marginTop: 8, flexWrap: 'wrap' }}>
              {r.tags.map((t, j) => <Pill key={j} variant="success" size="sm">{t}</Pill>)}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// L-9) PROFILE — Individuel ↔ Entreprise
// ─────────────────────────────────────────────────────────────
function LProfileScreen({ nav, onSwitchRole, profileType, setProfileType }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      {/* Curved hero */}
      <div style={{
        background: `linear-gradient(160deg, #C68426 0%, #8E5A00 100%)`,
        padding: '8px 16px 70px', borderRadius: '0 0 32px 32px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="truck" size={140} style={{ position: 'absolute', right: -20, top: 0, opacity: .08, color: '#fff' }}/>
        <ScreenHeader title="Profil livreur" dark transparent right={<IconBtn name="moreV" light style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '0 4px' }}>
          <Avatar name={profileType === 'company' ? 'Express Logistics' : 'Eric Mballa'} size={64} variant="accent" light/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 17, fontFamily: T.fontDisplay, fontWeight: 800, letterSpacing: '-0.01em' }}>
              {profileType === 'company' ? 'Express Logistics SARL' : 'Eric Mballa'}
            </div>
            <div style={{ fontSize: 12, opacity: .85, marginTop: 2 }}>
              {profileType === 'company' ? 'Entreprise · Douala 🇨🇲' : 'Indépendant · Douala 🇨🇲'}
            </div>
            <div style={{ marginTop: 6, display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <Pill variant="accent" size="sm"><Icon name="shieldCheck" size={10} color="#1a0f00"/> KYC VALIDÉ</Pill>
              <Pill variant="dark" size="sm">★ 4,8 · 218 avis</Pill>
            </div>
          </div>
        </div>
      </div>

      {/* Stats */}
      <div style={{ padding: '0 16px', marginTop: -50, position: 'relative' }}>
        <div style={{
          background: T.surface, borderRadius: 20, padding: 16,
          border: `1px solid ${T.line}`, boxShadow: T.shadowMd,
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12,
        }}>
          <Stat v="148" l="Livraisons"/>
          <Stat v="98 %" l="À l'heure" sep/>
          <Stat v="1,42M" l="CA mai"/>
        </div>
      </div>

      <div style={{ padding: '20px 16px' }}>
        {/* Profile type toggle */}
        <div style={{
          background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 12, marginBottom: 16,
        }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Type de profil</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {[
              { id: 'individual', icon: 'user', name: 'Indépendant', sub: 'Moto / Hiace personnel' },
              { id: 'company', icon: 'package', name: 'Entreprise', sub: 'Flotte multi-véhicules' },
            ].map(p => {
              const active = profileType === p.id;
              return (
                <button key={p.id} onClick={() => setProfileType(p.id)} style={{
                  padding: 12, borderRadius: 12, cursor: 'pointer',
                  background: active ? T.primarySoft : T.surface,
                  border: `1.5px solid ${active ? T.primary : T.line}`,
                  boxShadow: active ? `0 0 0 3px ${T.primarySoft}` : 'none',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
                  transition: `border-color ${T.duration} ${T.ease}`,
                }}>
                  <div style={{
                    width: 38, height: 38, borderRadius: 10,
                    background: active ? T.primary : T.surface2,
                    color: active ? '#fff' : T.ink2,
                    display: 'grid', placeItems: 'center',
                  }}>
                    <Icon name={p.icon} size={18}/>
                  </div>
                  <div style={{ fontSize: 12.5, fontWeight: 700, color: active ? T.primaryDark : T.ink }}>{p.name}</div>
                  <div style={{ fontSize: 10.5, color: T.ink3, textAlign: 'center', lineHeight: 1.3 }}>{p.sub}</div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Fleet (visible if company) */}
        {profileType === 'company' && (
          <MenuGroup title="Flotte (6 véhicules)" items={[
            { ic: 'truck', l: 'Camion 10 T · Mercedes', s: 'En course · Douala → Yaoundé', badge: '4', tone: 'warn' },
            { ic: 'truck', l: 'Hiace × 3', s: 'Disponibles · Douala' },
            { ic: 'truck', l: 'Moto express × 2', s: 'Disponibles · centre-ville' },
            { ic: 'plus', l: 'Ajouter un véhicule', s: 'Nouveau plaque + assurance' },
          ]}/>
        )}

        {/* Vehicle (visible if individual) */}
        {profileType === 'individual' && (
          <MenuGroup title="Mon véhicule" items={[
            { ic: 'truck', l: 'Toyota Hiace 2018', s: 'CE 882 GH · 1,5 T · assurance OK', badge: 'OK', tone: 'success' },
            { ic: 'shieldCheck', l: 'Permis B', s: 'Valide jusqu\'au 03/2028' },
            { ic: 'edit', l: 'Photos du véhicule', s: '4 photos publiques' },
          ]}/>
        )}

        <MenuGroup title="Zones desservies" items={[
          { ic: 'mapPin', l: 'Axe Douala — Yaoundé', s: 'Tarif moy. 75 k FCFA · 245 km' },
          { ic: 'mapPin', l: 'Douala intra-ville', s: '< 50 km · tarif depuis 5 k' },
          { ic: 'plus', l: 'Ajouter une zone', s: 'Élargir votre couverture' },
        ]}/>

        <MenuGroup title="Compte" items={[
          { ic: 'shieldCheck', l: 'Documents KYC', s: 'CNI · Carte grise · Assurance', badge: 'OK', tone: 'success' },
          { ic: 'star', l: 'Avis acheteurs', s: '218 avis · 4,8 ★', onClick: () => nav('l-reviews') },
          { ic: 'wallet', l: 'Gains et retraits', s: '384 200 F disponibles', onClick: () => nav('l-earnings') },
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
          Marché CM · espace livreur v2.1
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Livreur bottom nav
// ─────────────────────────────────────────────────────────────
function LBottomNav({ active, onNavigate }) {
  const items = [
    { id: 'l-dashboard', icon: 'home', label: 'Accueil' },
    { id: 'l-bids', icon: 'scale', label: 'Demandes', badge: 12 },
    { id: 'l-shipments', icon: 'truck', label: 'Mes courses', badge: 2 },
    { id: 'l-earnings', icon: 'wallet', label: 'Gains' },
    { id: 'l-profile', icon: 'user', label: 'Profil' },
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
            color: isActive ? T.primary : T.ink3, minHeight: 56,
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
                  fontFeatureSettings: '"tnum"',
                }}>{it.badge}</span>
              )}
            </div>
            <span style={{ fontSize: 10.5, fontWeight: 600, color: isActive ? T.primary : T.ink3, whiteSpace: 'nowrap' }}>{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

Object.assign(window, {
  LDashboardScreen, LBidsScreen, LQuoteScreen, LShipmentsScreen,
  LShipmentDetailScreen, LProofScreen, LEarningsScreen, LReviewsScreen, LProfileScreen,
  LBottomNav, MapBg, PartyCard,
});
