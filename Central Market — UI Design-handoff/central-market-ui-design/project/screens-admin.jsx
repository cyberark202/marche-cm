/*
 * Marché CM — Admin General screens (GENERAL_ADMIN)
 * 11 écrans : Dashboard, Utilisateurs, Détail utilisateur, KYC inbox,
 * Revue KYC, Litiges, Détail litige + décision, Réconciliation wallet,
 * Audit/Transactions, Config plateforme, Profil admin
 */

// ─────────────────────────────────────────────────────────────
// A-1) ADMIN DASHBOARD
// ─────────────────────────────────────────────────────────────
function ADashboardScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg, paddingBottom: 16 }}>
      {/* Dark authoritative header */}
      <div style={{
        background: `linear-gradient(160deg, #1A2A24 0%, ${T.ink} 100%)`,
        padding: '12px 16px 30px',
        borderRadius: '0 0 28px 28px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <div style={{ position: 'absolute', right: -30, top: -30, width: 180, height: 180, borderRadius: '50%', background: `radial-gradient(circle, rgba(245,180,0,.1) 0%, transparent 70%)` }}/>
        <Icon name="shield" size={140} style={{ position: 'absolute', right: -20, bottom: -40, opacity: .04, color: '#fff' }}/>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <Avatar name="Admin General" size={42} variant="accent" light/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11.5, opacity: .75, fontWeight: 600, letterSpacing: '.06em', textTransform: 'uppercase' }}>Administration · Marché CM</div>
            <div style={{ fontSize: 15, fontWeight: 700, fontFamily: T.fontDisplay, display: 'flex', alignItems: 'center', gap: 6 }}>
              Kerian Nkomo
              <Pill variant="accent" size="sm">SUPER ADMIN</Pill>
            </div>
          </div>
          <IconBtn name="bell" light badge={9} style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>
        </div>

        {/* GMV */}
        <div style={{ marginTop: 18 }}>
          <div style={{ fontSize: 11, opacity: .65, fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase' }}>Volume traité · mai 2026</div>
          <div style={{ fontSize: 32, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 2 }}>
            684,2 M<span style={{ fontSize: 14, opacity: .6, fontWeight: 600, marginLeft: 6 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .8, marginTop: 4, display: 'flex', gap: 14 }}>
            <span><Icon name="trending" size={11} style={{ display: 'inline', marginRight: 4, verticalAlign: 'middle', color: T.accent }}/> 1 248 commandes</span>
            <span style={{ width: 2, background: 'rgba(255,255,255,.2)' }}/>
            <span>Commission 20,5 M</span>
          </div>
        </div>
      </div>

      {/* KPI grid */}
      <div style={{ padding: '0 16px', marginTop: -18, position: 'relative' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <KpiCard ic="user" tone="info" v="12 480" label="Utilisateurs" sub="+182 cette sem." actionLabel="Voir" onAction={() => nav('a-users')}/>
          <KpiCard ic="shield" tone="warn" v="142,8 M" label="Séquestre actif" sub="84 commandes" actionLabel="Détail" onAction={() => nav('a-reconcile')}/>
          <KpiCard ic="flag" tone="coral" v="6" label="Litiges ouverts" sub="2 urgents" actionLabel="Traiter" onAction={() => nav('a-disputes')}/>
          <KpiCard ic="shieldCheck" tone="success" v="14" label="KYC à valider" sub="dont 3 vendeurs" actionLabel="Revue" onAction={() => nav('a-kyc')}/>
        </div>
      </div>

      {/* Critical alerts */}
      <div style={{ padding: '14px 16px 0' }}>
        <Alert tone="danger" ic="flag" title="Litige urgent · #62B1F0"
          sub="Marchandise endommagée · 1,8 M FCFA en attente de décision"
          cta="Décider" onClick={() => nav('a-dispute-detail')}/>
        <Alert tone="warn" ic="refresh" title="Écart de réconciliation NotchPay"
          sub="Différence de 184 500 F détectée à 09:00"
          cta="Rapprocher" onClick={() => nav('a-reconcile')}/>
        <Alert tone="info" ic="shieldCheck" title="14 documents KYC en attente"
          sub="Plus ancien : Tropical Foods · soumis il y a 2 j"
          cta="Revue" onClick={() => nav('a-kyc')}/>
      </div>

      {/* GMV chart */}
      <Section title="Volume hebdomadaire">
        <div style={{ padding: '0 16px' }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16 }}>
            <MiniChart values={[0.42, 0.55, 0.48, 0.7, 0.62, 0.85, 1.0]} labels={['L','M','M','J','V','S','D']}/>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 12 }}>
              <div>
                <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>Volume sem.</div>
                <div style={{ fontSize: 22, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.01em' }}>168 M <span style={{ fontSize: 11, color: T.ink3, fontWeight: 600 }}>FCFA</span></div>
              </div>
              <Pill variant="success"><Icon name="trending" size={11} color={T.primaryDark} strokeWidth={3}/>+22 %</Pill>
            </div>
          </div>
        </div>
      </Section>

      {/* Roles breakdown */}
      <Section title="Répartition utilisateurs">
        <div style={{ padding: '0 16px' }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16, display: 'flex', alignItems: 'center', gap: 16 }}>
            <Donut centerValue="12,5K" centerLabel="utilisateurs" segs={[
              { v: 9420, color: T.info, l: 'Acheteurs' },
              { v: 1820, color: T.primary, l: 'Vendeurs' },
              { v: 840, color: T.accent, l: 'Livreurs' },
              { v: 400, color: T.coral, l: 'Admins' },
            ]}/>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[
                { c: T.info, l: 'Acheteurs', v: '9 420' },
                { c: T.primary, l: 'Vendeurs', v: '1 820' },
                { c: T.accent, l: 'Livreurs', v: '840' },
                { c: T.coral, l: 'Admins', v: '400' },
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

      {/* Recent audit feed */}
      <Section title="Activité récente" action="Tout" onAction={() => nav('a-audit')}>
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { ic: 'shieldCheck', tone: 'success', t: 'KYC validé · AfricaTrade SARL', s: 'par Kerian N. · 14:22' },
            { ic: 'flag', tone: 'coral', t: 'Litige ouvert · CMD #62B1F0', s: 'par Awa Kamga · 13:48' },
            { ic: 'user', tone: 'info', t: 'Compte créé · Restaurant La Falaise', s: 'inscription email · 13:10' },
            { ic: 'refresh', tone: 'warn', t: 'Wallet reconcilié · NotchPay', s: 'auto · 09:00' },
          ].map((a, i) => (
            <div key={i} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10,
              display: 'flex', alignItems: 'center', gap: 10,
            }}>
              <div style={{
                width: 32, height: 32, borderRadius: 9, display: 'grid', placeItems: 'center',
                background: a.tone === 'success' ? T.primarySoft :
                            a.tone === 'coral' ? T.coralSoft :
                            a.tone === 'warn' ? T.accentSoft : '#E0E7FF',
                color: a.tone === 'success' ? T.primaryDark :
                       a.tone === 'coral' ? T.coral :
                       a.tone === 'warn' ? '#8E5A00' : '#3730A3',
              }}><Icon name={a.ic} size={15}/></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.t}</div>
                <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 1 }}>{a.s}</div>
              </div>
            </div>
          ))}
        </div>
      </Section>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-2) USERS list
// ─────────────────────────────────────────────────────────────
function AUsersScreen({ nav }) {
  const [tab, setTab] = React.useState('Tous');
  const users = [
    { name: 'Awa Kamga', role: 'Acheteur', city: 'Douala', kyc: 'OK', last: 'En ligne', tone: 'info' },
    { name: 'Tropical Foods', role: 'Vendeur', city: 'Douala', kyc: 'OK', last: '2 min', tone: 'primary' },
    { name: 'Express Logistics', role: 'Livreur', city: 'Douala', kyc: 'OK', last: '5 min', tone: 'accent' },
    { name: 'AfricaTrade', role: 'Vendeur', city: 'Yaoundé', kyc: 'EN ATTENTE', last: 'hier', tone: 'primary', pending: true },
    { name: 'Eric Mballa', role: 'Livreur', city: 'Douala', kyc: 'OK', last: 'En ligne', tone: 'accent' },
    { name: 'Restaurant La Falaise', role: 'Acheteur', city: 'Yaoundé', kyc: 'OK', last: '3 j', tone: 'info' },
    { name: 'Marie Sonkin', role: 'Acheteur', city: 'Bafoussam', kyc: 'REJETÉ', last: '1 sem', tone: 'info', rejected: true },
    { name: 'SOTRAM Cameroun', role: 'Livreur', city: 'Douala', kyc: 'OK', last: '2 j', tone: 'accent' },
  ];
  const filtered = tab === 'Tous' ? users : users.filter(u => u.role === tab);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Utilisateurs" subtitle="12 480 comptes" right={<><IconBtn name="search"/><IconBtn name="filter"/></>}/>

      {/* Search */}
      <div style={{ padding: '4px 16px 10px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          background: T.surface, padding: '0 14px',
          border: `1px solid ${T.line}`, borderRadius: 14, minHeight: 44,
        }}>
          <Icon name="search" size={16} color={T.ink3}/>
          <input placeholder="Nom, email, téléphone…" style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 13.5 }}/>
        </div>
      </div>

      {/* Role chips */}
      <div style={{ display: 'flex', gap: 6, padding: '0 16px 10px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['Tous', 'Acheteur', 'Vendeur', 'Livreur', 'KYC en attente', 'Suspendus'].map(c => (
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
        {filtered.map((u, i, arr) => (
          <button key={i} onClick={() => nav('a-user-detail')} style={{
            width: '100%', display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 16px', border: 'none', background: 'transparent', cursor: 'pointer',
            textAlign: 'left',
            borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
          }}>
            <Avatar name={u.name} size={42} variant={u.tone}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 14, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{u.name}</span>
                {u.pending && <Pill variant="warn" size="sm">KYC ?</Pill>}
                {u.rejected && <Pill variant="danger" size="sm">REJETÉ</Pill>}
              </div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                <span>{u.role}</span>
                <span style={{ width: 3, height: 3, background: T.ink4, borderRadius: 2 }}/>
                <Icon name="mapPin" size={10}/> {u.city}
                <span style={{ width: 3, height: 3, background: T.ink4, borderRadius: 2 }}/>
                <span>{u.last}</span>
              </div>
            </div>
            <Icon name="chevronR" size={16} color={T.ink3}/>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-3) USER DETAIL
// ─────────────────────────────────────────────────────────────
function AUserDetailScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      {/* Hero */}
      <div style={{
        background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
        padding: '8px 16px 70px', borderRadius: '0 0 28px 28px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <ScreenHeader onBack={() => nav('a-users')} title="Fiche utilisateur" dark transparent right={<IconBtn name="moreV" light style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '0 4px' }}>
          <Avatar name="Tropical Foods" size={64} variant="accent" light/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 17, fontWeight: 800, letterSpacing: '-0.01em' }}>Tropical Foods SARL</div>
            <div style={{ fontSize: 12, opacity: .8, marginTop: 2 }}>Vendeur · Douala · ID #USR-4A2F8B</div>
            <div style={{ marginTop: 6, display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <Pill variant="accent" size="sm"><Icon name="shieldCheck" size={10} color="#1a0f00"/> KYC VALIDÉ</Pill>
              <Pill variant="dark" size="sm">★ 4,6</Pill>
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
          <Stat v="42" l="Commandes"/>
          <Stat v="14,8M" l="CA total" sep/>
          <Stat v="0" l="Litiges"/>
        </div>
      </div>

      <div style={{ padding: '20px 16px' }}>
        {/* Coordonnées */}
        <MenuGroup title="Coordonnées" items={[
          { ic: 'mail', l: 'contact@tropicalfoods.cm', s: 'Email vérifié', badge: 'OK', tone: 'success' },
          { ic: 'phone', l: '+237 6 82 14 04 82', s: 'Mobile Money lié' },
          { ic: 'mapPin', l: 'Douala, Bonabéri', s: 'Entrepôt principal' },
        ]}/>

        {/* KYC */}
        <MenuGroup title="Conformité KYC" items={[
          { ic: 'shieldCheck', l: 'Registre du commerce', s: 'RC/DLA/2019/B/04829 · validé', badge: 'OK', tone: 'success' },
          { ic: 'shieldCheck', l: 'CNI dirigeant', s: 'M. Mballa Pierre · validé', badge: 'OK', tone: 'success' },
          { ic: 'shieldCheck', l: 'NIU fiscal', s: 'M032100245823Y · validé', badge: 'OK', tone: 'success' },
          { ic: 'calendar', l: 'Expiration', s: '12/2026 · 7 mois restants' },
        ]}/>

        {/* Wallet */}
        <MenuGroup title="Portefeuille" items={[
          { ic: 'wallet', l: 'Solde disponible', s: '8 420 000 FCFA' },
          { ic: 'shield', l: 'Séquestré', s: '2 900 000 FCFA · 3 commandes' },
          { ic: 'trending', l: 'CA mai', s: '14,8 M · +18 %' },
        ]}/>

        {/* Audit */}
        <MenuGroup title="Activité récente" items={[
          { ic: 'package', l: 'Commande #84F2 acceptée', s: 'il y a 12 min' },
          { ic: 'scale', l: 'RFQ répondue · La Falaise', s: '38 min' },
          { ic: 'shieldCheck', l: 'KYC validé', s: '12/2025 · par admin' },
        ]}/>

        {/* Actions */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginTop: 8 }}>
          <Btn variant="outline" size="md" icon="mail">Message</Btn>
          <Btn variant="outline" size="md" icon="refresh">Réinit. PIN</Btn>
        </div>
        <button style={{
          width: '100%', marginTop: 8, padding: 14, borderRadius: 14,
          background: T.coralSoft, color: T.coral, border: 'none',
          fontWeight: 700, fontSize: 14, cursor: 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          <Icon name="x" size={16} strokeWidth={2.4}/> Suspendre le compte
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-4) KYC INBOX
// ─────────────────────────────────────────────────────────────
function AKycScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Conformité KYC" subtitle="14 documents en attente"/>

      <div style={{ display: 'flex', gap: 6, padding: '0 16px 12px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['À traiter 14', 'Validés', 'Rejetés', 'Tous'].map((c, i) => (
          <button key={c} style={{
            flexShrink: 0, padding: '7px 12px', borderRadius: 999,
            background: i === 0 ? T.ink : T.surface,
            color: i === 0 ? '#fff' : T.ink2,
            border: `1px solid ${i === 0 ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 700, cursor: 'pointer',
            whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {[
          { name: 'AfricaTrade SARL', role: 'Vendeur', docs: 3, since: '2 jours', tone: 'primary', urgent: true },
          { name: 'Restaurant La Falaise', role: 'Acheteur', docs: 1, since: '1 jour', tone: 'info' },
          { name: 'Mototaxis Express', role: 'Livreur (entreprise)', docs: 5, since: '4 jours', tone: 'accent', urgent: true },
          { name: 'Mama Ngozi', role: 'Acheteur', docs: 1, since: '12 h', tone: 'info' },
          { name: 'Cocoa Cameroon', role: 'Vendeur', docs: 4, since: '8 h', tone: 'primary' },
        ].map((u, i) => (
          <button key={i} onClick={() => nav('a-kyc-review')} style={{
            width: '100%', background: T.surface,
            border: `1px solid ${u.urgent ? T.coral : T.line}`,
            borderRadius: 14, padding: 12, cursor: 'pointer', textAlign: 'left',
            boxShadow: u.urgent ? `0 0 0 3px ${T.coralSoft}` : 'none',
            display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <Avatar name={u.name} size={40} variant={u.tone}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 13.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{u.name}</span>
                {u.urgent && <Pill variant="danger" size="sm">URGENT</Pill>}
              </div>
              <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>{u.role} · {u.docs} document{u.docs > 1 ? 's' : ''} · soumis il y a {u.since}</div>
            </div>
            <Icon name="chevronR" size={16} color={T.ink3}/>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-5) KYC REVIEW
// ─────────────────────────────────────────────────────────────
function AKycReviewScreen({ nav }) {
  const [doc, setDoc] = React.useState(0);
  const docs = [
    { type: 'Registre du commerce', code: 'RC', valid: 'RC/DLA/2024/B/72018', tone: 'accent' },
    { type: 'CNI dirigeant', code: 'CNI', valid: 'CM-N°038472918', tone: 'sky' },
    { type: 'NIU fiscal', code: 'NIU', valid: 'M061800123456P', tone: 'primary' },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('a-kyc')} title="Revue KYC" subtitle="AfricaTrade SARL"/>

      {/* Doc viewer */}
      <div style={{ padding: '4px 16px 10px' }}>
        <div style={{ position: 'relative', borderRadius: 16, overflow: 'hidden', background: T.surface, border: `1px solid ${T.line}` }}>
          <Ph icon="package" height={240} radius={0} tone={docs[doc].tone} label={`${docs[doc].code} — DOCUMENT SCANNÉ`}/>
          {/* Floating doc info */}
          <div style={{
            position: 'absolute', top: 10, left: 10,
            background: 'rgba(255,255,255,.95)', padding: '6px 10px', borderRadius: 10,
            fontSize: 11, fontWeight: 700, color: T.ink, fontFamily: T.fontMono,
          }}>{docs[doc].valid}</div>
          <div style={{
            position: 'absolute', bottom: 10, right: 10, display: 'flex', gap: 6,
          }}>
            <IconBtn name="search" style={{ background: 'rgba(255,255,255,.92)' }}/>
            <IconBtn name="share" style={{ background: 'rgba(255,255,255,.92)' }}/>
          </div>
        </div>

        {/* Doc tabs */}
        <div style={{ display: 'flex', gap: 6, marginTop: 10, overflowX: 'auto', scrollbarWidth: 'none' }}>
          {docs.map((d, i) => (
            <button key={i} onClick={() => setDoc(i)} style={{
              flexShrink: 0, padding: '8px 12px', borderRadius: 10,
              background: doc === i ? T.ink : T.surface,
              color: doc === i ? '#fff' : T.ink2,
              border: `1px solid ${doc === i ? T.ink : T.line}`,
              fontSize: 12, fontWeight: 700, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 6,
            }}>
              <span style={{ fontSize: 10, padding: '1px 6px', borderRadius: 4, background: doc === i ? 'rgba(255,255,255,.2)' : T.surface2 }}>{d.code}</span>
              {d.type}
            </button>
          ))}
        </div>
      </div>

      {/* Validation checklist */}
      <div style={{ flex: 1, overflow: 'auto', padding: '6px 16px 16px' }}>
        <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Vérifications</div>
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 4 }}>
          {[
            { l: 'Document lisible', ok: true },
            { l: 'Tampons officiels visibles', ok: true },
            { l: 'Date de validité OK', ok: true },
            { l: 'Identité concorde avec compte', ok: true },
            { l: 'Adresse cohérente', ok: false },
          ].map((c, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '10px 12px',
              borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <span style={{
                width: 22, height: 22, borderRadius: 6,
                background: c.ok ? T.primarySoft : T.surface2,
                border: `1.5px solid ${c.ok ? T.primary : T.line}`,
                display: 'grid', placeItems: 'center', color: T.primary,
              }}>
                {c.ok && <Icon name="check" size={12} strokeWidth={3}/>}
              </span>
              <span style={{ fontSize: 13, fontWeight: 600, color: T.ink2 }}>{c.l}</span>
            </div>
          ))}
        </div>

        {/* Note */}
        <div style={{ marginTop: 14 }}>
          <label style={{ fontSize: 12, fontWeight: 700, color: T.ink2, marginLeft: 4, marginBottom: 6, display: 'block' }}>Commentaire interne</label>
          <textarea defaultValue="Adresse fournie diffère du registre. Demander preuve de domicile complémentaire." style={{
            width: '100%', padding: 12, borderRadius: 14,
            border: `1.5px solid ${T.line}`, background: T.surface,
            fontSize: 13, color: T.ink, fontFamily: T.fontBody,
            minHeight: 70, resize: 'vertical', outline: 'none', lineHeight: 1.5,
          }}/>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '10px 14px', display: 'flex', gap: 8, flexShrink: 0 }}>
        <Btn variant="outline" size="md" style={{ flex: 1, color: T.coral, borderColor: T.coralSoft }} icon="x">Rejeter</Btn>
        <Btn variant="primary" size="md" style={{ flex: 2 }} icon="check" onClick={() => nav('a-kyc')}>Valider le KYC</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-6) DISPUTES
// ─────────────────────────────────────────────────────────────
function ADisputesScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Litiges" subtitle="6 ouverts · 2 urgents" right={<IconBtn name="filter"/>}/>

      <div style={{ display: 'flex', gap: 6, padding: '0 16px 12px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['Ouverts 6', 'En arbitrage', 'Décidés', 'Tous'].map((c, i) => (
          <button key={c} style={{
            flexShrink: 0, padding: '7px 12px', borderRadius: 999,
            background: i === 0 ? T.ink : T.surface,
            color: i === 0 ? '#fff' : T.ink2,
            border: `1px solid ${i === 0 ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 700, cursor: 'pointer', whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {[
          { id: '#62B1F0', amount: '1 800 000', reason: 'Marchandise endommagée', parties: 'Awa Kamga vs SOTRAM', age: '2 j', urgent: true },
          { id: '#7C3A91', amount: '420 000', reason: 'Retard de livraison', parties: 'Hôtel Akwa vs Express L.', age: '1 j', urgent: true },
          { id: '#9D2E40', amount: '85 000', reason: 'Quantité incorrecte', parties: 'Restaurant LF vs Tropical', age: '4 j' },
          { id: '#3F18C2', amount: '210 000', reason: 'Produit non conforme', parties: 'Marché Mokolo vs AfricaT.', age: '6 j' },
        ].map((d, i) => (
          <button key={i} onClick={() => nav('a-dispute-detail')} style={{
            width: '100%', background: T.surface,
            border: `1px solid ${d.urgent ? T.coral : T.line}`,
            borderRadius: 14, padding: 12, cursor: 'pointer', textAlign: 'left',
            boxShadow: d.urgent ? `0 0 0 3px ${T.coralSoft}` : 'none',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <Pill variant={d.urgent ? 'danger' : 'warn'} size="sm">
                <Icon name="flag" size={10} color={d.urgent ? T.coral : '#8E5A00'}/>
                {d.urgent ? 'URGENT' : 'OUVERT'}
              </Pill>
              <span style={{ fontSize: 10, color: T.ink3, fontFamily: T.fontMono }}>LIT {d.id}</span>
              <span style={{ marginLeft: 'auto', fontSize: 11, color: T.ink3 }}>{d.age}</span>
            </div>
            <div style={{ fontSize: 14, fontWeight: 700, color: T.ink, lineHeight: 1.3 }}>{d.reason}</div>
            <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 3 }}>{d.parties}</div>
            <div style={{ marginTop: 8, padding: '8px 10px', background: T.surface2, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontSize: 11, color: T.ink2, fontWeight: 600 }}>Séquestre concerné</span>
              <span style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{d.amount} <span style={{ fontSize: 10, color: T.ink3 }}>FCFA</span></span>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-7) DISPUTE DETAIL — full arbitration screen
// ─────────────────────────────────────────────────────────────
function ADisputeDetailScreen({ nav }) {
  const [decision, setDecision] = React.useState(null);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('a-disputes')} title="Arbitrage" subtitle="LIT #62B1F0"/>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {/* Amount card */}
        <div style={{
          background: `linear-gradient(135deg, ${T.coral} 0%, #B91C1C 100%)`,
          color: '#fff', borderRadius: 18, padding: 16, position: 'relative', overflow: 'hidden',
        }}>
          <Icon name="flag" size={120} style={{ position: 'absolute', right: -20, bottom: -25, opacity: .15 }}/>
          <Pill variant="dark" size="sm">SÉQUESTRE GELÉ</Pill>
          <div style={{ fontSize: 28, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.02em', marginTop: 6 }}>
            1 800 000<span style={{ fontSize: 13, opacity: .8, marginLeft: 4, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .85, marginTop: 3 }}>
            Marchandise endommagée à la livraison · ouvert il y a 2 jours
          </div>
        </div>

        {/* Parties */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginTop: 12 }}>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10 }}>
            <div style={{ fontSize: 10, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>Plaignant</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
              <Avatar name="Awa Kamga" size={32} variant="info"/>
              <div>
                <div style={{ fontSize: 12.5, fontWeight: 700 }}>Awa Kamga</div>
                <div style={{ fontSize: 10, color: T.ink3 }}>Acheteur · Yaoundé</div>
              </div>
            </div>
          </div>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10 }}>
            <div style={{ fontSize: 10, color: T.ink3, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>Mis en cause</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
              <Avatar name="SOTRAM Cameroun" size={32} variant="dark"/>
              <div>
                <div style={{ fontSize: 12.5, fontWeight: 700 }}>SOTRAM Cameroun</div>
                <div style={{ fontSize: 10, color: T.ink3 }}>Livreur · Douala</div>
              </div>
            </div>
          </div>
        </div>

        {/* Timeline */}
        <div style={{ marginTop: 14 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Chronologie</div>
          <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 12 }}>
            {[
              { ic: 'flag', who: 'Awa Kamga', t: 'A ouvert le litige', d: '18 mai · 14:22', detail: '« 30 bidons sur 200 sont percés à la livraison. Photos jointes. »' },
              { ic: 'package', who: 'SOTRAM', t: 'A répondu', d: '18 mai · 16:05', detail: '« Bidons étaient OK au chargement. Photos d\'enlèvement jointes. »' },
              { ic: 'shieldCheck', who: 'Tropical Foods', t: 'A apporté témoignage', d: '19 mai · 09:30', detail: '« Confirmation emballage standard, état neuf. »' },
            ].map((e, i) => (
              <div key={i} style={{
                display: 'flex', gap: 10, padding: '10px 0',
                borderTop: i ? `1px dashed ${T.line2}` : 'none',
              }}>
                <div style={{ width: 32, height: 32, borderRadius: 9, background: T.surface2, color: T.ink2, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
                  <Icon name={e.ic} size={14}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 12, color: T.ink, fontWeight: 700 }}>{e.who} <span style={{ color: T.ink3, fontWeight: 500 }}>{e.t}</span></div>
                  <div style={{ fontSize: 10, color: T.ink3, marginTop: 1 }}>{e.d}</div>
                  <div style={{ fontSize: 12, color: T.ink2, marginTop: 4, fontStyle: 'italic', lineHeight: 1.4 }}>{e.detail}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Evidence */}
        <div style={{ marginTop: 14 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8 }}>Preuves jointes (5)</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
            {['accent', 'cream', 'primary', 'sky', 'coral'].map((tone, i) => (
              <div key={i} style={{ aspectRatio: '1 / 1', borderRadius: 10, overflow: 'hidden' }}>
                <Ph icon="camera" height="100%" radius={0} tone={tone} label={`PHOTO ${i+1}`}/>
              </div>
            ))}
          </div>
        </div>

        {/* Decision panel */}
        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11.5, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 10 }}>Décision d'arbitrage</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[
              { id: 'buyer', t: 'Remboursement intégral à l\'acheteur', s: '1 800 000 F → Awa · livreur déduit', tone: 'info' },
              { id: 'split', t: 'Partage 50 / 50', s: '900 k acheteur, 900 k livreur', tone: 'warn' },
              { id: 'seller', t: 'Décision en faveur du livreur', s: 'Séquestre libéré normalement', tone: 'success' },
            ].map(o => {
              const active = decision === o.id;
              return (
                <button key={o.id} onClick={() => setDecision(o.id)} style={{
                  width: '100%', padding: 12, borderRadius: 12, cursor: 'pointer',
                  background: active ? T.primarySoft : T.surface,
                  border: `1.5px solid ${active ? T.primary : T.line}`,
                  display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left',
                  boxShadow: active ? `0 0 0 3px ${T.primarySoft}` : 'none',
                }}>
                  <span style={{
                    width: 20, height: 20, borderRadius: '50%',
                    background: active ? T.primary : T.surface,
                    border: `2px solid ${active ? T.primary : T.line}`,
                    display: 'grid', placeItems: 'center',
                  }}>{active && <span style={{ width: 8, height: 8, background: '#fff', borderRadius: '50%' }}/>}</span>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 700, color: active ? T.primaryDark : T.ink }}>{o.t}</div>
                    <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 1 }}>{o.s}</div>
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '10px 14px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full icon="check" onClick={() => nav('a-disputes')}>
          Appliquer la décision
        </Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-8) WALLET RECONCILIATION
// ─────────────────────────────────────────────────────────────
function AReconcileScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Réconciliation wallet" subtitle="NotchPay · 09:00 UTC" right={<IconBtn name="refresh"/>}/>

      {/* Big balance card */}
      <div style={{ padding: '0 16px 12px' }}>
        <div style={{
          background: `linear-gradient(140deg, #1A2A24 0%, ${T.ink} 100%)`,
          borderRadius: 22, padding: 20, color: '#fff', position: 'relative', overflow: 'hidden',
        }}>
          <Icon name="wallet" size={140} style={{ position: 'absolute', right: -25, top: -25, opacity: .06, color: '#fff' }}/>
          <div style={{ fontSize: 11, opacity: .65, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Solde plateforme escrow</div>
          <div style={{ fontSize: 32, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.025em', marginTop: 4 }}>
            142 820 500<span style={{ fontSize: 14, opacity: .6, marginLeft: 6, fontWeight: 600 }}>FCFA</span>
          </div>
          <div style={{ fontSize: 11.5, opacity: .7, marginTop: 4 }}>84 commandes séquestrées · 12 livreurs actifs</div>
        </div>
      </div>

      {/* Reconcile cards */}
      <div style={{ padding: '0 16px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.04em' }}>Comptes attendus vs provider</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 10 }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 10.5, color: T.ink3 }}>Système Marché CM</div>
              <div style={{ fontSize: 17, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>142 820 500</div>
            </div>
            <span style={{ width: 1, height: 30, background: T.line }}/>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 10.5, color: T.ink3 }}>NotchPay reporté</div>
              <div style={{ fontSize: 17, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>142 636 000</div>
            </div>
          </div>
          <div style={{
            marginTop: 10, padding: '8px 10px',
            background: T.accentSoft, borderRadius: 10,
            display: 'flex', alignItems: 'center', gap: 8,
          }}>
            <Icon name="flag" size={16} color="#8E5A00"/>
            <div style={{ fontSize: 11.5, color: '#8E5A00', flex: 1 }}>
              Écart de <b>− 184 500 FCFA</b> · 0,13 %
            </div>
            <Btn variant="dark" size="sm">Détail</Btn>
          </div>
        </div>

        {/* Suspect txns */}
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ padding: '12px 14px', borderBottom: `1px solid ${T.line2}`, fontSize: 12, fontWeight: 800, color: T.ink2, textTransform: 'uppercase', letterSpacing: '.04em' }}>
            Transactions à rapprocher (4)
          </div>
          {[
            { t: 'CHK·NCH-48A2', s: 'Recharge 500 k · MTN · délai 4 h', v: '+ 500 000', tone: 'warn' },
            { t: 'DSB·NCH-29F1', s: 'Payout 320 k · Express Logistics · échec', v: '− 320 000', tone: 'coral' },
            { t: 'WBH·NCH-1E03', s: 'Webhook reçu sans transaction associée', v: '+ 84 000', tone: 'info' },
            { t: 'CHK·NCH-7B12', s: 'Status PENDING > 6 h · à vérifier', v: '+ 250 000', tone: 'warn' },
          ].map((t, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '10px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <div style={{
                width: 32, height: 32, borderRadius: 9, display: 'grid', placeItems: 'center',
                background: t.tone === 'warn' ? T.accentSoft : t.tone === 'coral' ? T.coralSoft : '#E0E7FF',
                color: t.tone === 'warn' ? '#8E5A00' : t.tone === 'coral' ? T.coral : '#3730A3',
              }}><Icon name="refresh" size={14}/></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12, fontFamily: T.fontMono, fontWeight: 700 }}>{t.t}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{t.s}</div>
              </div>
              <div style={{ fontSize: 12.5, fontWeight: 700, fontFeatureSettings: '"tnum"' }}>{t.v}</div>
            </div>
          ))}
        </div>

        <Btn variant="primary" size="md" full icon="check">Marquer rapproché</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-9) AUDIT / Transactions
// ─────────────────────────────────────────────────────────────
function AAuditScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader title="Audit & journaux" subtitle="Activité plateforme" right={<><IconBtn name="filter"/><IconBtn name="share"/></>}/>

      <div style={{ display: 'flex', gap: 6, padding: '0 16px 10px', overflowX: 'auto', scrollbarWidth: 'none' }}>
        {['Tous', 'Wallet', 'Commandes', 'KYC', 'Litiges', 'Auth'].map((c, i) => (
          <button key={c} style={{
            flexShrink: 0, padding: '7px 12px', borderRadius: 999,
            background: i === 0 ? T.ink : T.surface,
            color: i === 0 ? '#fff' : T.ink2,
            border: `1px solid ${i === 0 ? T.ink : T.line}`,
            fontSize: 12, fontWeight: 700, cursor: 'pointer', whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px' }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: T.ink3, marginBottom: 8 }}>AUJOURD'HUI · 20 MAI 2026</div>
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14, overflow: 'hidden' }}>
          {[
            { t: '15:42', ic: 'flag', tone: 'coral', who: 'Awa Kamga', a: 'Litige ouvert', meta: 'CMD #62B1F0 · 1 800 000 F' },
            { t: '14:22', ic: 'shieldCheck', tone: 'success', who: 'Admin Kerian', a: 'KYC validé', meta: 'AfricaTrade SARL · #USR-7F31' },
            { t: '13:10', ic: 'user', tone: 'info', who: 'Système', a: 'Compte créé', meta: 'La Falaise · acheteur' },
            { t: '12:45', ic: 'wallet', tone: 'warn', who: 'NotchPay', a: 'Webhook reçu', meta: 'CHK-NCH-48A2 · SUCCESS' },
            { t: '11:30', ic: 'package', tone: 'success', who: 'Tropical Foods', a: 'Commande acceptée', meta: 'CMD #84F2E1B · 2,32 M' },
            { t: '09:00', ic: 'refresh', tone: 'warn', who: 'Cron', a: 'Réconciliation auto', meta: 'Écart 184 500 F détecté' },
          ].map((e, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 14px', borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10, display: 'grid', placeItems: 'center',
                background: e.tone === 'success' ? T.primarySoft :
                            e.tone === 'coral' ? T.coralSoft :
                            e.tone === 'warn' ? T.accentSoft : '#E0E7FF',
                color: e.tone === 'success' ? T.primaryDark :
                       e.tone === 'coral' ? T.coral :
                       e.tone === 'warn' ? '#8E5A00' : '#3730A3',
              }}><Icon name={e.ic} size={15}/></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12.5, fontWeight: 700, color: T.ink }}>{e.who} · <span style={{ color: T.ink2, fontWeight: 500 }}>{e.a}</span></div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 1, fontFamily: T.fontMono }}>{e.meta}</div>
              </div>
              <div style={{ fontSize: 11, color: T.ink3, fontWeight: 600, fontFamily: T.fontMono }}>{e.t}</div>
            </div>
          ))}
        </div>

        <Btn variant="outline" size="md" full icon="share" style={{ marginTop: 14 }}>Exporter audit (CSV)</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-10) PLATFORM CONFIG
// ─────────────────────────────────────────────────────────────
function AConfigScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader title="Configuration" subtitle="Plateforme · sécurité"/>

      <div style={{ padding: '4px 16px 16px' }}>
        <MenuGroup title="Commissions" items={[
          { ic: 'scale', l: 'Commission plateforme', s: '3 % sur chaque commande', badge: '3 %', tone: 'success' },
          { ic: 'truck', l: 'Part transitaire', s: '5 % du séquestre' },
          { ic: 'package', l: 'Part vendeur', s: '92 % à la libération' },
          { ic: 'refresh', l: 'Frais NotchPay', s: '1 % paiement, 0,5 % retrait' },
        ]}/>

        <MenuGroup title="Sécurité & escrow" items={[
          { ic: 'shield', l: 'Délai max séquestre', s: '14 jours · puis arbitrage auto' },
          { ic: 'lock', l: 'PIN wallet obligatoire', s: 'Pour tous les retraits', badge: 'ACTIF', tone: 'success' },
          { ic: 'mail', l: '2FA email', s: 'Validation 2 étapes' },
          { ic: 'shieldCheck', l: 'Chiffrement PII at-rest', s: 'AES-256 · clé rotation 90 j' },
        ]}/>

        <MenuGroup title="Notifications & alertes" items={[
          { ic: 'bell', l: 'Webhooks NotchPay', s: 'Endpoint actif · 0 erreur 24h' },
          { ic: 'mail', l: 'Alertes FinOps', s: 'finops@marche.cm · seuil 100k' },
          { ic: 'globe', l: 'Statut plateforme', s: 'Tous services opérationnels', badge: 'OK', tone: 'success' },
        ]}/>

        <MenuGroup title="Modération" items={[
          { ic: 'flag', l: 'Mots-clés interdits', s: '42 termes filtrés' },
          { ic: 'package', l: 'Catégories restreintes', s: 'Armes, alcool fort, pharma' },
          { ic: 'user', l: 'Politique signalements', s: '3 strikes → suspension' },
        ]}/>

        <div style={{ textAlign: 'center', fontSize: 10.5, color: T.ink4, marginTop: 16 }}>
          Marché CM · console admin v2.1.4
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A-11) ADMIN PROFILE
// ─────────────────────────────────────────────────────────────
function AProfileScreen({ nav, onSwitchRole }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <div style={{
        background: `linear-gradient(160deg, #1A2A24 0%, ${T.ink} 100%)`,
        padding: '8px 16px 70px', borderRadius: '0 0 32px 32px',
        color: '#fff', position: 'relative', overflow: 'hidden',
      }}>
        <Icon name="shield" size={140} color="#fff" style={{ position: 'absolute', right: -20, top: 0, opacity: .06 }}/>
        <ScreenHeader title="Profil admin" dark transparent right={<IconBtn name="moreV" light style={{ background: 'rgba(255,255,255,.12)', border: '1px solid rgba(255,255,255,.18)' }}/>}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '0 4px' }}>
          <Avatar name="Kerian Nkomo" size={64} variant="accent" light/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 17, fontWeight: 800, letterSpacing: '-0.01em' }}>Kerian Nkomo</div>
            <div style={{ fontSize: 12, opacity: .8, marginTop: 2 }}>Admin général · Yaoundé 🇨🇲</div>
            <div style={{ marginTop: 6, display: 'flex', gap: 4 }}>
              <Pill variant="accent" size="sm"><Icon name="shieldCheck" size={10} color="#1a0f00"/> SUPER ADMIN</Pill>
              <Pill variant="dark" size="sm">2FA actif</Pill>
            </div>
          </div>
        </div>
      </div>

      <div style={{ padding: '0 16px', marginTop: -50, position: 'relative' }}>
        <div style={{
          background: T.surface, borderRadius: 20, padding: 16,
          border: `1px solid ${T.line}`, boxShadow: T.shadowMd,
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12,
        }}>
          <Stat v="124" l="Litiges traités"/>
          <Stat v="1 240" l="KYC validés" sep/>
          <Stat v="98 %" l="SLA tenu"/>
        </div>
      </div>

      <div style={{ padding: '20px 16px' }}>
        <MenuGroup title="Compte" items={[
          { ic: 'mail', l: 'kerian@marche.cm', s: 'Email professionnel' },
          { ic: 'lock', l: 'Mot de passe', s: 'Modifié il y a 14 jours' },
          { ic: 'shieldCheck', l: 'Authenticator', s: 'Google Authenticator actif', badge: 'OK', tone: 'success' },
        ]}/>

        <MenuGroup title="Permissions" items={[
          { ic: 'user', l: 'Gérer utilisateurs', s: 'Création, suspension', badge: 'ON', tone: 'success' },
          { ic: 'flag', l: 'Décider litiges', s: 'Arbitrage final', badge: 'ON', tone: 'success' },
          { ic: 'wallet', l: 'Wallet & FinOps', s: 'Réconciliation, retraits', badge: 'ON', tone: 'success' },
          { ic: 'shieldCheck', l: 'Validation KYC', s: 'Tous types de profil', badge: 'ON', tone: 'success' },
        ]}/>

        <MenuGroup title="Système" items={[
          { ic: 'edit', l: 'Configuration plateforme', s: 'Commissions, sécurité', onClick: () => nav('a-config') },
          { ic: 'share', l: 'Exporter audit complet', s: 'CSV chiffré' },
          { ic: 'globe', l: 'Tableau santé services', s: 'API, WS, DB, NotchPay' },
        ]}/>

        <button onClick={onSwitchRole} style={{
          width: '100%', marginTop: 8, padding: 14, borderRadius: 14,
          background: T.accent, color: '#1a0f00', border: 'none',
          fontWeight: 800, fontSize: 14, cursor: 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}><Icon name="refresh" size={16} strokeWidth={2.4}/> Basculer en mode Acheteur</button>

        <div style={{ textAlign: 'center', fontSize: 10.5, color: T.ink4, marginTop: 16, padding: 4 }}>
          Console admin · Marché CM v2.1.4
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Admin bottom nav
// ─────────────────────────────────────────────────────────────
function ABottomNav({ active, onNavigate }) {
  const items = [
    { id: 'a-dashboard', icon: 'home', label: 'Accueil' },
    { id: 'a-users', icon: 'user', label: 'Comptes' },
    { id: 'a-disputes', icon: 'flag', label: 'Litiges', badge: 6 },
    { id: 'a-reconcile', icon: 'wallet', label: 'Wallet' },
    { id: 'a-profile', icon: 'shield', label: 'Profil' },
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
  ADashboardScreen, AUsersScreen, AUserDetailScreen, AKycScreen, AKycReviewScreen,
  ADisputesScreen, ADisputeDetailScreen, AReconcileScreen, AAuditScreen, AConfigScreen, AProfileScreen,
  ABottomNav,
});
