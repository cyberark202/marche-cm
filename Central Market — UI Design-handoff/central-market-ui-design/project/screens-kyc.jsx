/*
 * Marché CM — KYC Onboarding flow
 * 6 écrans : intro, type, docs upload, signature, review, success
 */

function KycIntroScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('home')} title="Vérification KYC" subtitle="Étape obligatoire > 50 k F"/>
      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px 16px' }}>
        <div style={{
          background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          borderRadius: 22, padding: 22, color: '#fff', position: 'relative', overflow: 'hidden',
          boxShadow: T.shadowBrand,
        }}>
          <Icon name="shield" size={140} style={{ position: 'absolute', right: -25, top: -20, opacity: .12 }}/>
          <Icon name="star" size={50} color={T.accent} style={{ position: 'absolute', right: 30, top: 18, opacity: .35 }}/>
          <Pill variant="accent" size="sm">SÉCURISÉ · CHIFFRÉ AES-256</Pill>
          <h2 style={{ margin: '12px 0 6px', fontSize: 22, fontWeight: 800, letterSpacing: '-0.02em', lineHeight: 1.2 }}>
            Validez votre identité<br/>en moins de <span style={{ color: T.accent }}>3 minutes</span>
          </h2>
          <p style={{ margin: 0, fontSize: 12.5, opacity: .85, lineHeight: 1.5 }}>
            Conforme aux exigences GIMAC et BEAC pour le paiement Mobile Money.
          </p>
        </div>

        <div style={{ marginTop: 16 }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Ce dont vous aurez besoin</div>
          {[
            { ic: 'shieldCheck', t: "Pièce d'identité", s: 'CNI, passeport ou récépissé' },
            { ic: 'mapPin', t: 'Justificatif de domicile', s: 'Facture ENEO/CAMWATER < 3 mois' },
            { ic: 'phone', t: 'Numéro Mobile Money', s: 'MTN MoMo ou Orange Money actif' },
            { ic: 'edit', t: 'Signature manuscrite', s: 'Capturée à l\'étape finale' },
          ].map((r, i) => (
            <div key={i} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12,
              padding: 12, marginBottom: 8, display: 'flex', alignItems: 'center', gap: 12,
            }}>
              <div style={{ width: 36, height: 36, borderRadius: 10, background: T.primarySoft, color: T.primary, display: 'grid', placeItems: 'center' }}>
                <Icon name={r.ic} size={17}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 700 }}>{r.t}</div>
                <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{r.s}</div>
              </div>
              <Icon name="check" size={14} color={T.primary} strokeWidth={3}/>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 12, padding: 12, background: T.accentSoft, borderRadius: 12, display: 'flex', alignItems: 'flex-start', gap: 10 }}>
          <Icon name="lock" size={18} color="#8E5A00" style={{ marginTop: 2 }}/>
          <div style={{ fontSize: 11.5, color: '#8E5A00', lineHeight: 1.5 }}>
            Vos documents ne sont jamais partagés avec les autres utilisateurs. Stockés chiffrés.
          </div>
        </div>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('kyc-type')}>Commencer la vérification</Btn>
      </div>
    </div>
  );
}

function KycProgress({ step }) {
  return (
    <div style={{ padding: '0 16px 6px', display: 'flex', gap: 4, flexShrink: 0 }}>
      {[1,2,3,4].map(i => (
        <div key={i} style={{
          flex: 1, height: 4, borderRadius: 2,
          background: i <= step ? T.primary : T.surface2,
          transition: `background ${T.durationMd} ${T.ease}`,
        }}/>
      ))}
    </div>
  );
}

function KycTypeScreen({ nav }) {
  const [type, setType] = React.useState('individual');
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('kyc-intro')} title="Étape 1 / 4" subtitle="Type de compte"/>
      <KycProgress step={1}/>
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 16px' }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 800, letterSpacing: '-0.01em' }}>Qui êtes-vous ?</h3>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: T.ink3, lineHeight: 1.5 }}>
          Les documents demandés dépendent de votre profil.
        </p>

        {[
          { id: 'individual', icon: 'user', name: 'Particulier', sub: 'CNI · justificatif domicile' },
          { id: 'company', icon: 'package', name: 'Entreprise / SARL', sub: 'RC · NIU · CNI dirigeant' },
          { id: 'pro', icon: 'truck', name: 'Profession libérale', sub: 'Patente · CNI · attestation' },
        ].map(o => {
          const active = type === o.id;
          return (
            <button key={o.id} onClick={() => setType(o.id)} style={{
              width: '100%', padding: 16, marginBottom: 10, borderRadius: 16,
              background: active ? T.primarySoft : T.surface,
              border: `1.5px solid ${active ? T.primary : T.line}`,
              boxShadow: active ? `0 0 0 4px ${T.primarySoft}` : 'none',
              display: 'flex', alignItems: 'center', gap: 14, cursor: 'pointer', textAlign: 'left',
            }}>
              <div style={{
                width: 46, height: 46, borderRadius: 12,
                background: active ? T.primary : T.surface2,
                color: active ? '#fff' : T.ink2,
                display: 'grid', placeItems: 'center',
              }}><Icon name={o.icon} size={22}/></div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14.5, fontWeight: 700, color: active ? T.primaryDark : T.ink }}>{o.name}</div>
                <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>{o.sub}</div>
              </div>
              <span style={{
                width: 22, height: 22, borderRadius: '50%',
                border: `2px solid ${active ? T.primary : T.line}`,
                background: active ? T.primary : T.surface,
                display: 'grid', placeItems: 'center',
              }}>{active && <Icon name="check" size={12} color="#fff" strokeWidth={3}/>}</span>
            </button>
          );
        })}
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('kyc-docs')}>Continuer</Btn>
      </div>
    </div>
  );
}

function KycDocsScreen({ nav }) {
  const [docs, setDocs] = React.useState({ id: false, address: false, selfie: false });
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('kyc-type')} title="Étape 2 / 4" subtitle="Téléverser les documents"/>
      <KycProgress step={2}/>
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 16px' }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 800, letterSpacing: '-0.01em' }}>3 documents requis</h3>
        <p style={{ margin: '0 0 18px', fontSize: 13, color: T.ink3, lineHeight: 1.5 }}>
          Cliquez sur chaque case pour simuler la prise de photo.
        </p>

        {[
          { id: 'id', label: "Carte nationale d'identité", sub: 'Recto-verso, bonne lumière', icon: 'shield', tone: 'sky' },
          { id: 'address', label: 'Justificatif de domicile', sub: 'Facture ENEO < 3 mois', icon: 'mapPin', tone: 'accent' },
          { id: 'selfie', label: 'Selfie avec CNI', sub: 'Pour confirmer l\'identité', icon: 'camera', tone: 'primary' },
        ].map(d => {
          const done = docs[d.id];
          return (
            <button key={d.id} onClick={() => setDocs({...docs, [d.id]: !done})} style={{
              width: '100%', marginBottom: 12, padding: 0, background: T.surface, borderRadius: 16, cursor: 'pointer',
              overflow: 'hidden', textAlign: 'left',
              border: `1.5px solid ${done ? T.primary : T.line}`,
              boxShadow: done ? `0 0 0 3px ${T.primarySoft}` : T.shadowSm,
            }}>
              <div style={{ position: 'relative' }}>
                {done ? (
                  <Ph icon={d.icon} height={120} radius={0} tone={d.tone} label={`PHOTO ${d.id.toUpperCase()} CAPTURÉE`}/>
                ) : (
                  <div style={{
                    height: 120, background: T.surface2,
                    display: 'grid', placeItems: 'center', color: T.ink3,
                  }}>
                    <div style={{ textAlign: 'center' }}>
                      <Icon name="camera" size={30} strokeWidth={1.5}/>
                      <div style={{ fontSize: 11, fontWeight: 700, marginTop: 6 }}>TOUCHER POUR CAPTURER</div>
                    </div>
                  </div>
                )}
                {done && (
                  <div style={{
                    position: 'absolute', top: 8, right: 8,
                    width: 28, height: 28, borderRadius: '50%', background: T.primary,
                    display: 'grid', placeItems: 'center', color: '#fff',
                  }}><Icon name="check" size={14} strokeWidth={3}/></div>
                )}
              </div>
              <div style={{ padding: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13.5, fontWeight: 700, color: T.ink }}>{d.label}</div>
                  <div style={{ fontSize: 11, color: T.ink3, marginTop: 1 }}>{d.sub}</div>
                </div>
                {done && <Pill variant="success" size="sm">OK</Pill>}
              </div>
            </button>
          );
        })}
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('kyc-signature')}
          style={{ opacity: Object.values(docs).every(Boolean) ? 1 : 0.5 }}>
          Continuer ({Object.values(docs).filter(Boolean).length}/3)
        </Btn>
      </div>
    </div>
  );
}

function KycSignatureScreen({ nav }) {
  const [signed, setSigned] = React.useState(false);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('kyc-docs')} title="Étape 3 / 4" subtitle="Signature manuscrite"/>
      <KycProgress step={3}/>
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 16px' }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 800, letterSpacing: '-0.01em' }}>Signez avec votre doigt</h3>
        <p style={{ margin: '0 0 16px', fontSize: 13, color: T.ink3, lineHeight: 1.5 }}>
          Cette signature numérique vous engage légalement.
        </p>

        <div style={{
          background: T.surface, border: `2px dashed ${signed ? T.primary : T.line}`,
          borderRadius: 18, padding: 16,
        }}>
          <div style={{
            height: 180, background: signed ? '#FBFBF7' : T.surface, borderRadius: 12,
            display: 'grid', placeItems: 'center', overflow: 'hidden',
          }}>
            {signed ? (
              <svg width="220" height="80" viewBox="0 0 220 80" style={{ color: T.ink }}>
                <path d="M 20 50 Q 35 20, 50 45 T 80 45 Q 95 25, 110 55 T 140 50 Q 155 20, 175 50 L 200 35"
                  fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round"/>
                <path d="M 50 60 L 175 60" stroke="currentColor" strokeWidth="1" opacity=".4"/>
              </svg>
            ) : (
              <div style={{ textAlign: 'center', color: T.ink3 }}>
                <Icon name="edit" size={32} strokeWidth={1.5} style={{ margin: '0 auto' }}/>
                <div style={{ fontSize: 12, fontWeight: 600, marginTop: 8 }}>Signez ici</div>
              </div>
            )}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 10 }}>
            <button onClick={() => setSigned(false)} style={{
              background: 'none', border: 'none', color: T.ink3, fontSize: 12,
              fontWeight: 700, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 4,
            }}><Icon name="refresh" size={13}/> Recommencer</button>
            <Btn variant="dark" size="sm" onClick={() => setSigned(true)}>Simuler signature</Btn>
          </div>
        </div>

        <div style={{ marginTop: 16, padding: 12, background: T.primarySoft, borderRadius: 12, fontSize: 11.5, color: T.primaryDark, lineHeight: 1.5 }}>
          En signant, je reconnais avoir lu et accepté les <b>CGU</b> et la <b>Politique de confidentialité</b> de Marché CM.
        </div>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight"
          onClick={() => nav('kyc-review')}
          style={{ opacity: signed ? 1 : 0.5 }}>Valider ma signature</Btn>
      </div>
    </div>
  );
}

function KycReviewScreen({ nav }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('kyc-signature')} title="Étape 4 / 4" subtitle="Récapitulatif"/>
      <KycProgress step={4}/>
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 16px' }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 20, fontWeight: 800, letterSpacing: '-0.01em' }}>Tout est prêt</h3>
        <p style={{ margin: '0 0 16px', fontSize: 13, color: T.ink3, lineHeight: 1.5 }}>
          Vérifiez avant l'envoi à notre équipe de conformité.
        </p>

        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14, marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Avatar name="Awa Kamga" size={48} variant="primary"/>
            <div>
              <div style={{ fontSize: 15, fontWeight: 700 }}>Awa Kamga</div>
              <div style={{ fontSize: 11.5, color: T.ink3 }}>Particulier · Douala</div>
            </div>
          </div>
        </div>

        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, overflow: 'hidden' }}>
          {[
            { l: 'Type de compte', v: 'Particulier' },
            { l: 'CNI', v: 'Capturée ✓' },
            { l: 'Justificatif domicile', v: 'Capturé ✓' },
            { l: 'Selfie avec CNI', v: 'Capturé ✓' },
            { l: 'Signature numérique', v: 'Validée ✓' },
            { l: 'Mobile Money', v: '+237 6 82 14 04 82' },
          ].map((r, i, arr) => (
            <div key={i} style={{
              padding: '11px 14px', display: 'flex', justifyContent: 'space-between',
              borderBottom: i < arr.length - 1 ? `1px solid ${T.line2}` : 'none',
            }}>
              <span style={{ fontSize: 12.5, color: T.ink3, fontWeight: 600 }}>{r.l}</span>
              <span style={{ fontSize: 12.5, color: T.ink, fontWeight: 700 }}>{r.v}</span>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 12, padding: 12, background: T.accentSoft, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
          <Icon name="clock" size={18} color="#8E5A00"/>
          <div style={{ fontSize: 11.5, color: '#8E5A00', lineHeight: 1.5 }}>
            <b>Délai de traitement</b> : 24 h ouvrées. Vous recevrez un email à validation.
          </div>
        </div>
      </div>
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full icon="send" onClick={() => nav('kyc-success')}>Envoyer pour vérification</Btn>
      </div>
    </div>
  );
}

function KycSuccessScreen({ nav }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
      color: '#fff', padding: 24, alignItems: 'center', justifyContent: 'center',
      position: 'relative', overflow: 'hidden',
    }}>
      <Icon name="star" size={140} color={T.accent} style={{ position: 'absolute', right: -30, top: 60, opacity: .1 }}/>
      <Icon name="star" size={80} color={T.accent} style={{ position: 'absolute', left: 0, bottom: 180, opacity: .1 }}/>

      <div style={{
        width: 120, height: 120, borderRadius: '50%',
        background: T.accent, color: '#1a0f00',
        display: 'grid', placeItems: 'center',
        animation: 'kycPop 600ms cubic-bezier(.34,1.56,.64,1) both',
        boxShadow: `0 20px 40px -10px rgba(245,180,0,.5)`,
      }}>
        <Icon name="check" size={64} strokeWidth={3}/>
      </div>

      <div style={{ textAlign: 'center', marginTop: 28, animation: 'kycFade 700ms ease 200ms both' }}>
        <h2 style={{ margin: 0, fontSize: 28, fontWeight: 800, letterSpacing: '-0.02em', lineHeight: 1.1 }}>Dossier envoyé !</h2>
        <p style={{ margin: '10px 0 0', fontSize: 14, opacity: .85, lineHeight: 1.5, maxWidth: 280 }}>
          Notre équipe vérifiera vos documents sous 24 h.
        </p>
      </div>

      <div style={{ marginTop: 28, width: '100%', maxWidth: 300, animation: 'kycFade 800ms ease 400ms both' }}>
        <Btn variant="accent" size="lg" full icon="bell" onClick={() => nav('notifications')}>Voir mes notifications</Btn>
        <button onClick={() => nav('home')} style={{
          background: 'none', border: 'none', color: '#fff', opacity: .7, cursor: 'pointer',
          width: '100%', padding: 12, marginTop: 8, fontSize: 13, fontWeight: 600,
        }}>Retour à l'accueil</button>
      </div>

      <style>{`
        @keyframes kycPop { 0% { transform: scale(.4); opacity: 0; } 100% { transform: scale(1); opacity: 1; } }
        @keyframes kycFade { 0% { transform: translateY(10px); opacity: 0; } 100% { transform: translateY(0); opacity: 1; } }
      `}</style>
    </div>
  );
}

Object.assign(window, {
  KycIntroScreen, KycTypeScreen, KycDocsScreen, KycSignatureScreen,
  KycReviewScreen, KycSuccessScreen, KycProgress,
});
