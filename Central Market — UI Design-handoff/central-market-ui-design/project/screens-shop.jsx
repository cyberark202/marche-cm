/*
 * Marché CM — Screens part A
 * Splash, Login, Home, Catalog, Product Detail, Cart, Checkout
 */

// ─────────────────────────────────────────────────────────────
// 1) SPLASH — Brand intro with logo
// ─────────────────────────────────────────────────────────────
function SplashScreen({ nav }) {
  React.useEffect(() => {
    const t = setTimeout(() => nav('login'), 1800);
    return () => clearTimeout(t);
  }, []);
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'space-between',
      padding: '24px 24px 48px',
      background: `radial-gradient(120% 80% at 50% 30%, ${T.primary} 0%, ${T.primaryDeep} 80%)`,
      color: '#fff', position: 'relative', overflow: 'hidden',
    }}>
      {/* decorative star bursts */}
      <div style={{ position: 'absolute', inset: 0, opacity: .12, pointerEvents: 'none' }}>
        <Icon name="star" size={120} color={T.accent} style={{ position: 'absolute', top: 80, left: -30 }}/>
        <Icon name="star" size={80} color={T.accent} style={{ position: 'absolute', top: 200, right: -20 }}/>
        <Icon name="star" size={50} color={T.accent} style={{ position: 'absolute', bottom: 220, left: 40 }}/>
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{
          animation: 'logoIn 600ms cubic-bezier(.34,1.56,.64,1) both',
        }}>
          <Logo size={108} mono={false}/>
        </div>
        <div style={{
          marginTop: 24, textAlign: 'center',
          animation: 'fadeUp 700ms ease 200ms both',
        }}>
          <div style={{
            fontFamily: T.fontDisplay, fontWeight: 800,
            fontSize: 36, letterSpacing: '-0.025em', lineHeight: 1.05,
          }}>Marché<span style={{color: T.accent}}>.</span>cm</div>
          <div style={{
            marginTop: 6, fontSize: 13, opacity: .8, letterSpacing: '.08em',
            textTransform: 'uppercase', fontWeight: 600,
          }}>Le marché central du Cameroun</div>
        </div>
      </div>

      <div style={{ width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, animation: 'fadeUp 800ms ease 400ms both' }}>
        <div style={{
          width: 32, height: 32, borderRadius: '50%',
          border: `2.5px solid ${T.accent}`, borderTopColor: 'transparent',
          animation: 'spin 1s linear infinite',
        }}/>
        <div style={{ fontSize: 12, opacity: .7, letterSpacing: '.04em' }}>Connexion sécurisée…</div>
      </div>

      <style>{`
        @keyframes logoIn { 0% { transform: scale(.6) translateY(20px); opacity: 0; } 100% { transform: scale(1) translateY(0); opacity: 1; } }
        @keyframes fadeUp { 0% { transform: translateY(12px); opacity: 0; } 100% { transform: translateY(0); opacity: 1; } }
        @keyframes spin { to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 2) LOGIN — Email + Google + guest
// ─────────────────────────────────────────────────────────────
function LoginScreen({ nav }) {
  const [showPass, setShowPass] = React.useState(false);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      {/* Hero strip */}
      <div style={{
        background: `linear-gradient(160deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
        padding: '24px 24px 36px',
        borderRadius: '0 0 32px 32px',
        color: '#fff',
        position: 'relative', overflow: 'hidden',
      }}>
        <div style={{ position: 'absolute', top: -30, right: -30, width: 160, height: 160, borderRadius: '50%', background: 'rgba(245,180,0,.15)' }}/>
        <div style={{ position: 'absolute', bottom: -40, left: -20, width: 120, height: 120, borderRadius: '50%', background: 'rgba(255,255,255,.06)' }}/>

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 28 }}>
          <Logo size={36} withWordmark light/>
          <button onClick={() => nav('home')} style={{ background: 'none', border: 'none', color: '#fff', opacity: .8, fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
            Mode invité →
          </button>
        </div>
        <h1 style={{ margin: 0, fontFamily: T.fontDisplay, fontSize: 28, fontWeight: 800, letterSpacing: '-0.02em', lineHeight: 1.1 }}>
          Bonjour 👋<br/>
          <span style={{ color: T.accent }}>Connectez-vous</span> pour commencer.
        </h1>
        <p style={{ margin: '10px 0 0', fontSize: 13.5, opacity: .85, lineHeight: 1.5 }}>
          Achetez en gros ou en détail. Paiement Mobile Money sécurisé.
        </p>
      </div>

      {/* Form */}
      <div style={{ flex: 1, padding: '22px 22px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Field label="E-mail" icon="mail" placeholder="vous@example.cm" value="awa.kamga@email.cm"/>
        <Field label="Mot de passe" icon="lock" placeholder="••••••••"
          type={showPass ? 'text' : 'password'}
          value="bonjour123"
          right={
            <button onClick={() => setShowPass(!showPass)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: T.ink3, padding: 4 }}>
              <Icon name={showPass ? 'eyeOff' : 'eye'} size={18}/>
            </button>
          }/>

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: -2 }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: T.ink2, cursor: 'pointer' }}>
            <span style={{
              width: 18, height: 18, borderRadius: 5, background: T.primary,
              display: 'grid', placeItems: 'center', color: '#fff',
            }}><Icon name="check" size={12} strokeWidth={3}/></span>
            Se souvenir
          </label>
          <a style={{ fontSize: 13, color: T.primary, fontWeight: 600, cursor: 'pointer' }}>Mot de passe oublié ?</a>
        </div>

        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('home')}>
          Se connecter
        </Btn>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '8px 0' }}>
          <div style={{ flex: 1, height: 1, background: T.line }}/>
          <span style={{ fontSize: 12, color: T.ink3, fontWeight: 600 }}>OU CONTINUER AVEC</span>
          <div style={{ flex: 1, height: 1, background: T.line }}/>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <Btn variant="outline" size="md" icon="google" onClick={() => nav('home')}>Google</Btn>
          <Btn variant="outline" size="md" icon="phone" onClick={() => nav('home')}>OTP SMS</Btn>
        </div>

        <div style={{ textAlign: 'center', marginTop: 'auto', paddingTop: 16, fontSize: 13, color: T.ink3 }}>
          Pas encore de compte ? <a style={{ color: T.primary, fontWeight: 700, cursor: 'pointer' }}>S'inscrire</a>
        </div>
      </div>
    </div>
  );
}

function Field({ label, icon, placeholder, type = 'text', value, right }) {
  const [focused, setFocused] = React.useState(false);
  const [v, setV] = React.useState(value || '');
  return (
    <div>
      <label style={{ fontSize: 12, fontWeight: 700, color: T.ink2, marginLeft: 4, marginBottom: 6, display: 'block', letterSpacing: '.02em' }}>{label}</label>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        background: T.surface, padding: '0 14px',
        border: `1.5px solid ${focused ? T.primary : T.line}`,
        borderRadius: 14,
        minHeight: 52,
        boxShadow: focused ? `0 0 0 4px ${T.primarySoft}` : 'none',
        transition: `border-color ${T.duration} ${T.ease}, box-shadow ${T.duration} ${T.ease}`,
      }}>
        {icon && <Icon name={icon} size={18} color={focused ? T.primary : T.ink3}/>}
        <input
          type={type} placeholder={placeholder} value={v}
          onChange={e => setV(e.target.value)}
          onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
          style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontSize: 15, color: T.ink, fontFamily: T.fontBody,
            minHeight: 48,
          }}
        />
        {right}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 3) HOME — landing with categories, featured products, wallet shortcut
// ─────────────────────────────────────────────────────────────
function HomeScreen({ nav }) {
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg, paddingBottom: 16 }}>
      {/* Greeting + bell */}
      <div style={{ padding: '12px 16px 8px', display: 'flex', alignItems: 'center', gap: 12 }}>
        <Avatar name="Awa Kamga" size={40} variant="primary"/>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12, color: T.ink3, fontWeight: 600 }}>Bonjour,</div>
          <div style={{ fontSize: 15, fontWeight: 700, color: T.ink, fontFamily: T.fontDisplay, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Awa Kamga 🇨🇲</div>
        </div>
        <IconBtn name="qr"/>
        <IconBtn name="bell" badge={3}/>
      </div>

      {/* Search */}
      <div style={{ padding: '8px 16px 12px' }}>
        <button onClick={() => nav('catalog')} style={{
          width: '100%', display: 'flex', alignItems: 'center', gap: 10,
          background: T.surface, padding: '0 14px',
          border: `1px solid ${T.line}`, borderRadius: 14,
          minHeight: 50, cursor: 'pointer',
          textAlign: 'left',
        }}>
          <Icon name="search" size={18} color={T.ink3}/>
          <span style={{ flex: 1, fontSize: 14, color: T.ink3 }}>Rechercher huile, riz, ciment…</span>
          <span style={{
            width: 32, height: 32, borderRadius: 9, background: T.primary, color: '#fff',
            display: 'grid', placeItems: 'center',
          }}><Icon name="filter" size={16}/></span>
        </button>
      </div>

      {/* Wallet card (hero) */}
      <div style={{ padding: '4px 16px 16px' }}>
        <div onClick={() => nav('wallet')} style={{
          background: `linear-gradient(135deg, ${T.primary} 0%, ${T.primaryDeep} 100%)`,
          borderRadius: 20, padding: 20, color: '#fff', position: 'relative', overflow: 'hidden',
          cursor: 'pointer', boxShadow: T.shadowBrand,
        }}>
          <div style={{ position: 'absolute', right: -20, bottom: -20, width: 140, height: 140, borderRadius: '50%', background: 'radial-gradient(circle, rgba(245,180,0,.18) 0%, transparent 70%)' }}/>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <span style={{ fontSize: 11, letterSpacing: '.08em', opacity: .8, fontWeight: 700, textTransform: 'uppercase' }}>Mon portefeuille</span>
            <Icon name="wallet" size={18} color="rgba(255,255,255,.7)"/>
          </div>
          <div style={{ fontSize: 28, fontWeight: 800, fontFeatureSettings: '"tnum"', letterSpacing: '-0.02em' }}>1 248 500<span style={{ fontSize: 13, opacity: .7, marginLeft: 6 }}>FCFA</span></div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <button onClick={(e) => { e.stopPropagation(); nav('topup'); }} style={{
              flex: 1, padding: '11px 12px', borderRadius: 11, border: 'none',
              background: T.accent, color: '#1a0f00', fontWeight: 700, fontSize: 13, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            }}><Icon name="plus" size={14} strokeWidth={2.5}/> Recharger</button>
            <button style={{
              flex: 1, padding: '11px 12px', borderRadius: 11,
              background: 'rgba(255,255,255,.12)', color: '#fff', border: '1px solid rgba(255,255,255,.2)',
              fontWeight: 700, fontSize: 13, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            }}><Icon name="arrowRight" size={14} strokeWidth={2.5}/> Envoyer</button>
          </div>
        </div>
      </div>

      {/* Categories */}
      <Section title="Catégories">
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10, padding: '0 16px' }}>
          {[
            { icon: 'tag', label: 'Alimentation', tone: 'primary' },
            { icon: 'package', label: 'Textile', tone: 'accent' },
            { icon: 'grid', label: 'Électro', tone: 'sky' },
            { icon: 'flame', label: 'Beauté', tone: 'coral' },
            { icon: 'truck', label: 'BTP', tone: 'cream' },
            { icon: 'mountain', label: 'Agro', tone: 'primary' },
            { icon: 'globe', label: 'Import', tone: 'sky' },
            { icon: 'scale', label: 'RFQ B2B', tone: 'accent' },
          ].map((c, i) => (
            <button key={i} onClick={() => nav('catalog')} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14,
              padding: '12px 6px', cursor: 'pointer', display: 'flex', flexDirection: 'column',
              alignItems: 'center', gap: 6, minHeight: 80,
              transition: `transform ${T.duration} ${T.ease}, border-color ${T.duration} ${T.ease}`,
            }}>
              <Ph icon={c.icon} height={36} radius={10} tone={c.tone}/>
              <span style={{ fontSize: 11, fontWeight: 600, color: T.ink2, textAlign: 'center' }}>{c.label}</span>
            </button>
          ))}
        </div>
      </Section>

      {/* Promo banner */}
      <div style={{ padding: '4px 16px 16px' }}>
        <div style={{
          borderRadius: 18, padding: 16, display: 'flex', alignItems: 'center', gap: 12,
          background: `linear-gradient(115deg, ${T.accent} 0%, #FFC940 100%)`,
          color: '#1a0f00', boxShadow: T.shadowAccent, position: 'relative', overflow: 'hidden',
        }}>
          <div style={{ position: 'absolute', right: -10, top: -10, opacity: .15 }}>
            <Icon name="trophy" size={100}/>
          </div>
          <div style={{ flex: 1 }}>
            <Pill variant="dark" size="sm">PROMO RAMADAN</Pill>
            <div style={{ fontFamily: T.fontDisplay, fontWeight: 800, fontSize: 16, marginTop: 6, lineHeight: 1.2, letterSpacing: '-0.01em' }}>
              −20 % sur les sacs de riz de 50 kg
            </div>
            <div style={{ fontSize: 11, opacity: .8, marginTop: 2 }}>Jusqu'au 30 mai · 12 fournisseurs partenaires</div>
          </div>
        </div>
      </div>

      {/* Featured products */}
      <Section title="Populaires cette semaine" action="Voir tout" onAction={() => nav('catalog')}>
        <div style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '0 16px 4px', scrollbarWidth: 'none' }}>
          {[
            { name: 'Huile palme 20 L · Tropical', price: '14 500', sup: 'Tropical Foods', tone: 'accent', icon: 'package' },
            { name: 'Riz long grain 50 kg', price: '28 500', sup: 'Yaoundé Foods', tone: 'cream', icon: 'package', badge: '-15%' },
            { name: 'Cacao en fèves 60 kg', price: '42 000', sup: 'AfricaTrade', tone: 'primary', icon: 'tag' },
            { name: 'Ciment Dangote sac 50 kg', price: '6 200', sup: 'BTP Cameroun', tone: 'cream', icon: 'package' },
          ].map((p, i) => (
            <button key={i} onClick={() => nav('product')} style={{
              flexShrink: 0, width: 180, background: T.surface, border: `1px solid ${T.line}`,
              borderRadius: 16, overflow: 'hidden', cursor: 'pointer', textAlign: 'left',
              padding: 0,
            }}>
              <div style={{ position: 'relative' }}>
                <Ph icon={p.icon} height={130} radius={0} tone={p.tone}/>
                {p.badge && <span style={{
                  position: 'absolute', top: 8, left: 8,
                  padding: '3px 8px', background: T.coral, color: '#fff',
                  fontSize: 10, fontWeight: 800, borderRadius: 6, letterSpacing: '.04em',
                }}>{p.badge}</span>}
                <span style={{
                  position: 'absolute', top: 8, right: 8,
                  width: 30, height: 30, borderRadius: '50%', background: 'rgba(255,255,255,.95)',
                  display: 'grid', placeItems: 'center', color: T.ink2,
                }}><Icon name="heart" size={14}/></span>
              </div>
              <div style={{ padding: 12 }}>
                <div style={{ fontSize: 10, color: T.primary, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="check" size={10} color={T.primary} strokeWidth={3}/> {p.sup}
                </div>
                <div style={{ fontSize: 13, fontWeight: 600, color: T.ink, marginTop: 4, lineHeight: 1.3, height: 34, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                  {p.name}
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 8 }}>
                  <div>
                    <span style={{ fontSize: 15, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{p.price}</span>
                    <span style={{ fontSize: 10, color: T.ink3, marginLeft: 3, fontWeight: 600 }}>FCFA</span>
                  </div>
                  <span style={{
                    width: 30, height: 30, borderRadius: 9, background: T.ink, color: '#fff',
                    display: 'grid', placeItems: 'center',
                  }}><Icon name="plus" size={14} strokeWidth={2.5}/></span>
                </div>
              </div>
            </button>
          ))}
        </div>
      </Section>

      {/* RFQ teaser */}
      <Section title="Demande de devis B2B">
        <div style={{ padding: '0 16px' }}>
          <div onClick={() => nav('catalog')} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 16,
            display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer',
          }}>
            <Ph icon="scale" height={56} radius={12} tone="sky" />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontFamily: T.fontDisplay, fontWeight: 700, fontSize: 14, color: T.ink }}>Publier une RFQ</div>
              <div style={{ fontSize: 12, color: T.ink3, marginTop: 2, lineHeight: 1.4 }}>Décrivez votre besoin · les vendeurs vous envoient des offres</div>
            </div>
            <Icon name="chevronR" size={18} color={T.ink3}/>
          </div>
        </div>
      </Section>
    </div>
  );
}

function Section({ title, action, onAction, children }) {
  return (
    <div style={{ marginTop: 20 }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px', marginBottom: 12,
      }}>
        <h3 style={{
          margin: 0, fontFamily: T.fontDisplay, fontWeight: 700, fontSize: 16,
          color: T.ink, letterSpacing: '-0.01em',
        }}>{title}</h3>
        {action && <button onClick={onAction} style={{ background: 'none', border: 'none', cursor: 'pointer', color: T.primary, fontSize: 13, fontWeight: 700 }}>{action} →</button>}
      </div>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 4) CATALOG — Search results with filters
// ─────────────────────────────────────────────────────────────
function CatalogScreen({ nav }) {
  const [activeChip, setActiveChip] = React.useState('Tous');
  const products = [
    { name: 'Huile palme raffinée 20 L', sup: 'Tropical Foods', price: '14 500', tone: 'accent', icon: 'package', rating: 4.5, sales: '320 vendus' },
    { name: 'Riz long grain Premium 50 kg', sup: 'Yaoundé Foods', price: '28 500', tone: 'cream', icon: 'package', rating: 4.3, sales: '210 vendus', badge: '-15%' },
    { name: 'Cacao en fèves séchées 60 kg', sup: 'AfricaTrade', price: '42 000', tone: 'primary', icon: 'tag', rating: 4.7, sales: '88 vendus' },
    { name: 'Carton huile cuisson 1 L ×20', sup: 'Bafoussam Ind.', price: '11 200', tone: 'accent', icon: 'package', rating: 4.4, sales: '510 vendus' },
    { name: 'Ciment Dangote sac 50 kg', sup: 'BTP Cameroun', price: '6 200', tone: 'cream', icon: 'package', rating: 4.6, sales: '1 200 vendus' },
    { name: 'Sucre fin 50 kg origine SN', sup: 'Doual Trading', price: '23 800', tone: 'primary', icon: 'tag', rating: 4.2, sales: '74 vendus' },
  ];
  return (
    <div style={{ flex: 1, overflow: 'auto', background: T.bg }}>
      <ScreenHeader
        onBack={() => nav('home')}
        title="Catalogue"
        subtitle={`${products.length * 327} produits disponibles`}
        right={<><IconBtn name="filter"/><IconBtn name="sort"/></>}
      />

      {/* Search */}
      <div style={{ padding: '4px 16px 12px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          background: T.surface, padding: '0 14px',
          border: `1px solid ${T.line}`, borderRadius: 14,
          minHeight: 48,
        }}>
          <Icon name="search" size={18} color={T.ink3}/>
          <input defaultValue="huile palme" style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontSize: 14, color: T.ink,
          }}/>
          <Icon name="x" size={16} color={T.ink3}/>
        </div>
      </div>

      {/* Chips */}
      <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '0 16px 12px', scrollbarWidth: 'none' }}>
        {['Tous', 'Gros B2B', 'Détail', 'Bio certifié', 'Origine CM', 'Moins de 10k', 'Note 4.5+'].map(c => (
          <button key={c} onClick={() => setActiveChip(c)} style={{
            flexShrink: 0, padding: '8px 14px', borderRadius: 999,
            background: activeChip === c ? T.ink : T.surface,
            color: activeChip === c ? '#fff' : T.ink2,
            border: `1px solid ${activeChip === c ? T.ink : T.line}`,
            fontSize: 12.5, fontWeight: 600, cursor: 'pointer',
            transition: `all ${T.duration} ${T.ease}`,
            whiteSpace: 'nowrap',
          }}>{c}</button>
        ))}
      </div>

      {/* Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 16px 16px' }}>
        {products.map((p, i) => (
          <button key={i} onClick={() => nav('product')} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16,
            overflow: 'hidden', cursor: 'pointer', textAlign: 'left', padding: 0,
            transition: `transform ${T.duration} ${T.ease}, box-shadow ${T.duration} ${T.ease}`,
          }}>
            <div style={{ position: 'relative' }}>
              <Ph icon={p.icon} height={140} radius={0} tone={p.tone}/>
              {p.badge && <span style={{
                position: 'absolute', top: 8, left: 8,
                padding: '3px 7px', background: T.coral, color: '#fff',
                fontSize: 10, fontWeight: 800, borderRadius: 6,
              }}>{p.badge}</span>}
              <span style={{
                position: 'absolute', top: 8, right: 8,
                width: 28, height: 28, borderRadius: '50%', background: 'rgba(255,255,255,.92)',
                display: 'grid', placeItems: 'center', color: T.ink2,
              }}><Icon name="heart" size={13}/></span>
            </div>
            <div style={{ padding: 11 }}>
              <div style={{ fontSize: 10, color: T.primary, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                <Icon name="check" size={10} color={T.primary} strokeWidth={3}/>{p.sup}
              </div>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: T.ink, marginTop: 3, lineHeight: 1.3, height: 32, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{p.name}</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginTop: 5 }}>
                <Stars value={p.rating} size={10}/>
                <span style={{ fontSize: 10, color: T.ink3 }}>· {p.sales}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 8 }}>
                <div>
                  <span style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{p.price}</span>
                  <span style={{ fontSize: 10, color: T.ink3, marginLeft: 2, fontWeight: 600 }}>FCFA</span>
                </div>
                <span style={{
                  width: 28, height: 28, borderRadius: 8, background: T.ink, color: '#fff',
                  display: 'grid', placeItems: 'center',
                }}><Icon name="plus" size={12} strokeWidth={2.5}/></span>
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 5) PRODUCT DETAIL
// ─────────────────────────────────────────────────────────────
function ProductScreen({ nav }) {
  const [qty, setQty] = React.useState(200);
  const unit = 14500;
  const total = qty * unit;
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      {/* Image hero with floating header */}
      <div style={{ position: 'relative' }}>
        <Ph icon="package" height={260} radius={0} tone="accent" label="HUILE TROPICAL · 20 L"/>
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, padding: '8px 16px 10px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10,
        }}>
          <IconBtn name="arrowLeft" onClick={() => nav('catalog')}/>
          <div style={{ display: 'flex', gap: 8 }}>
            <IconBtn name="share"/>
            <IconBtn name="heart"/>
            <IconBtn name="bag" onClick={() => nav('cart')} badge={3}/>
          </div>
        </div>
        {/* thumbs */}
        <div style={{ position: 'absolute', bottom: 12, left: 16, display: 'flex', gap: 6 }}>
          {[0,1,2,3].map(i => <span key={i} style={{
            width: i === 0 ? 24 : 8, height: 8, borderRadius: 4,
            background: i === 0 ? T.ink : 'rgba(255,255,255,.7)',
            transition: `width ${T.duration} ${T.ease}`,
          }}/>)}
        </div>
      </div>

      {/* Sheet */}
      <div style={{
        flex: 1, background: T.bg, borderTopLeftRadius: 28, borderTopRightRadius: 28,
        marginTop: -22, padding: '20px 18px 100px', overflow: 'auto',
        position: 'relative', zIndex: 1,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
          <Pill variant="success" size="sm">GROS B2B</Pill>
          <Pill variant="warn" size="sm">ORIGINE CM</Pill>
        </div>
        <h1 style={{
          margin: 0, fontFamily: T.fontDisplay, fontWeight: 800, fontSize: 22, lineHeight: 1.2,
          letterSpacing: '-0.02em', color: T.ink,
        }}>Huile de palme raffinée — bidon 20 L</h1>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
          <Stars value={4.2}/>
          <span style={{ fontSize: 12, color: T.ink3, fontWeight: 600 }}>4,2 · 218 avis · 320 vendus</span>
        </div>

        {/* Supplier */}
        <div style={{
          marginTop: 14, padding: 12, background: T.surface, border: `1px solid ${T.line}`, borderRadius: 14,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <Avatar name="Tropical Foods" size={42} variant="primary"/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 13.5, fontWeight: 700, color: T.ink }}>Tropical Foods SARL</span>
              <Pill variant="success" size="sm"><Icon name="shieldCheck" size={10} color={T.primaryDark}/> KYC</Pill>
            </div>
            <div style={{ fontSize: 11.5, color: T.ink3, marginTop: 2 }}>Grossiste · Douala · Réponse en 2 h</div>
          </div>
          <button onClick={() => nav('chat-thread')} style={{
            padding: '8px 12px', borderRadius: 10, border: 'none',
            background: T.ink, color: '#fff', fontWeight: 700, fontSize: 12,
            display: 'inline-flex', alignItems: 'center', gap: 5, cursor: 'pointer',
          }}><Icon name="chat" size={13}/> Chat</button>
        </div>

        {/* Pricing tiers */}
        <div style={{
          marginTop: 14, padding: 16, borderRadius: 16,
          background: `linear-gradient(135deg, ${T.accentSoft} 0%, #FCE9B0 100%)`,
          border: `1px solid #F0E2BB`,
        }}>
          <div style={{ fontSize: 11, fontWeight: 800, color: '#8E5A00', letterSpacing: '.08em', textTransform: 'uppercase' }}>Prix à partir de</div>
          <div style={{ fontSize: 30, fontWeight: 800, fontFeatureSettings: '"tnum"', color: T.ink, marginTop: 2, letterSpacing: '-0.02em' }}>
            14 500<span style={{ fontSize: 13, color: T.ink2, marginLeft: 4, fontWeight: 600 }}>FCFA / bidon</span>
          </div>
          <div style={{ fontSize: 11.5, color: T.ink2, marginTop: 4 }}>Fourchette : 12 800 — 16 200 FCFA</div>
          <div style={{ marginTop: 12, fontSize: 12 }}>
            {[
              { q: '50 — 199', p: '16 200', d: '—' },
              { q: '200 — 999', p: '14 500', d: '−10 %' },
              { q: '1 000 — 5 000', p: '12 800', d: '−21 %' },
            ].map((t, i) => (
              <div key={i} style={{
                display: 'flex', justifyContent: 'space-between',
                padding: '7px 0', borderTop: i ? '1px dashed rgba(122,92,14,.18)' : 'none',
                fontFeatureSettings: '"tnum"',
                color: i === 1 ? T.primaryDark : T.ink2, fontWeight: i === 1 ? 700 : 500,
              }}>
                <span>{t.q} bidons</span>
                <span>{t.p} FCFA</span>
                <span style={{ minWidth: 40, textAlign: 'right' }}>{t.d}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Description */}
        <div style={{ marginTop: 16 }}>
          <h4 style={{ margin: '0 0 6px', fontFamily: T.fontDisplay, fontSize: 14, fontWeight: 700, color: T.ink }}>Description</h4>
          <p style={{ margin: 0, fontSize: 13, color: T.ink2, lineHeight: 1.55 }}>
            Huile de palme 100 % végétale, raffinée et désodorisée. Conditionnée en bidons hermétiques de 20 L pour restaurants, boulangeries et commerces de gros. Origine Cameroun, certifié RSPO.
          </p>
        </div>

        {/* Trust */}
        <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {[
            { ic: 'shieldCheck', t: 'Séquestre', d: 'Paiement bloqué' },
            { ic: 'truck', t: 'Transitaire', d: 'Au choix' },
            { ic: 'check', t: 'KYC validé', d: 'Vendeur vérifié' },
          ].map((x, i) => (
            <div key={i} style={{
              background: T.surface, border: `1px solid ${T.line}`, borderRadius: 12, padding: 10,
            }}>
              <Icon name={x.ic} size={18} color={T.primary}/>
              <div style={{ fontSize: 11.5, fontWeight: 700, color: T.ink, marginTop: 6 }}>{x.t}</div>
              <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 1 }}>{x.d}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Sticky bottom CTA */}
      <div style={{
        position: 'sticky', bottom: 0, background: T.surface,
        borderTop: `1px solid ${T.line2}`, padding: '10px 14px',
        display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0,
        boxShadow: '0 -8px 24px -8px rgba(14,31,24,.08)',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', background: T.surface2, borderRadius: 12, padding: 4,
        }}>
          <button onClick={() => setQty(Math.max(50, qty - 10))} style={{
            width: 36, height: 36, border: 'none', background: 'transparent', borderRadius: 8, cursor: 'pointer',
            display: 'grid', placeItems: 'center',
          }}><Icon name="minus" size={14} color={T.ink2} strokeWidth={2.5}/></button>
          <span style={{ width: 40, textAlign: 'center', fontWeight: 800, fontSize: 14, fontFeatureSettings: '"tnum"' }}>{qty}</span>
          <button onClick={() => setQty(qty + 10)} style={{
            width: 36, height: 36, border: 'none', background: 'transparent', borderRadius: 8, cursor: 'pointer',
            display: 'grid', placeItems: 'center',
          }}><Icon name="plus" size={14} color={T.ink2} strokeWidth={2.5}/></button>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 10, color: T.ink3, fontWeight: 600 }}>Total</div>
          <div style={{ fontSize: 16, fontWeight: 800, fontFeatureSettings: '"tnum"', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{total.toLocaleString('fr-FR')} <span style={{ fontSize: 10, color: T.ink3 }}>FCFA</span></div>
        </div>
        <Btn variant="primary" size="md" iconRight="arrowRight" onClick={() => nav('cart')}>Acheter</Btn>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 6) CART
// ─────────────────────────────────────────────────────────────
function CartScreen({ nav }) {
  const items = [
    { name: 'Huile palme raffinée 20 L', sup: 'Tropical Foods', qty: 200, unit: 14500, tone: 'accent', icon: 'package' },
    { name: 'Riz long grain 50 kg', sup: 'Yaoundé Foods', qty: 20, unit: 28500, tone: 'cream', icon: 'package' },
    { name: 'Ciment Dangote 50 kg', sup: 'BTP Cameroun', qty: 100, unit: 6200, tone: 'cream', icon: 'package' },
  ];
  const sub = items.reduce((s, i) => s + i.qty * i.unit, 0);
  const transit = 85000;
  const platform = Math.round(sub * 0.025);
  const total = sub + transit + platform;
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: T.bg }}>
      <ScreenHeader onBack={() => nav('product')} title="Panier" subtitle={`${items.length} articles`} right={<IconBtn name="trash"/>}/>

      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px' }}>
        {items.map((it, i) => (
          <div key={i} style={{
            background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16,
            padding: 12, marginBottom: 10, display: 'flex', gap: 12,
          }}>
            <Ph icon={it.icon} height={72} radius={10} tone={it.tone}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 10, color: T.primary, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 3 }}>
                <Icon name="check" size={10} color={T.primary} strokeWidth={3}/> {it.sup}
              </div>
              <div style={{ fontSize: 13, fontWeight: 600, color: T.ink, marginTop: 3, lineHeight: 1.3 }}>{it.name}</div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 8 }}>
                <div style={{ display: 'flex', alignItems: 'center', background: T.surface2, borderRadius: 8, padding: 2 }}>
                  <button style={{ width: 26, height: 26, border: 'none', background: 'transparent', borderRadius: 6, cursor: 'pointer', display: 'grid', placeItems: 'center' }}><Icon name="minus" size={12} color={T.ink2}/></button>
                  <span style={{ width: 30, textAlign: 'center', fontWeight: 700, fontSize: 12.5, fontFeatureSettings: '"tnum"' }}>{it.qty}</span>
                  <button style={{ width: 26, height: 26, border: 'none', background: 'transparent', borderRadius: 6, cursor: 'pointer', display: 'grid', placeItems: 'center' }}><Icon name="plus" size={12} color={T.ink2}/></button>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: 14, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{(it.qty * it.unit).toLocaleString('fr-FR')}</div>
                  <div style={{ fontSize: 10, color: T.ink3 }}>FCFA</div>
                </div>
              </div>
            </div>
          </div>
        ))}

        {/* Transit selection */}
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14, marginTop: 6 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
            <span style={{ fontFamily: T.fontDisplay, fontWeight: 700, fontSize: 14 }}>Transitaire</span>
            <a style={{ fontSize: 12, color: T.primary, fontWeight: 700 }}>Comparer →</a>
          </div>
          {[
            { name: 'Express Logistics', rating: 4.8, days: '5 j', price: '85 000', active: true },
            { name: 'SOTRAM Cameroun', rating: 4.5, days: '7 j', price: '62 000', active: false },
          ].map((x, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '10px 12px', borderRadius: 12, marginTop: i ? 6 : 0,
              background: x.active ? T.primarySoft : 'transparent',
              border: `1.5px solid ${x.active ? T.primary : T.line2}`,
              cursor: 'pointer',
            }}>
              <Avatar name={x.name} size={36} variant={x.active ? 'primary' : 'dark'}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 700 }}>{x.name}</div>
                <div style={{ fontSize: 11, color: T.ink3, display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Stars value={x.rating} size={10}/> {x.rating} · {x.days}
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 13, fontWeight: 800, fontFeatureSettings: '"tnum"' }}>{x.price}</div>
                <div style={{ fontSize: 10, color: T.ink3 }}>FCFA</div>
              </div>
              <span style={{
                width: 20, height: 20, borderRadius: '50%',
                background: x.active ? T.primary : T.surface,
                border: `2px solid ${x.active ? T.primary : T.line}`,
                display: 'grid', placeItems: 'center',
              }}>{x.active && <span style={{ width: 6, height: 6, background: '#fff', borderRadius: '50%' }}/>}</span>
            </div>
          ))}
        </div>

        {/* Summary */}
        <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: 16, padding: 14, marginTop: 10 }}>
          <SumRow l="Sous-total" v={`${sub.toLocaleString('fr-FR')} FCFA`}/>
          <SumRow l="Transitaire (Express)" v={`${transit.toLocaleString('fr-FR')} FCFA`}/>
          <SumRow l="Commission plateforme" v={`${platform.toLocaleString('fr-FR')} FCFA`}/>
          <div style={{ height: 1, background: T.line, margin: '10px 0' }}/>
          <SumRow l="Total à séquestrer" v={`${total.toLocaleString('fr-FR')} FCFA`} bold large/>
          <div style={{
            marginTop: 10, padding: '8px 10px', background: T.primarySoft, borderRadius: 10,
            display: 'flex', alignItems: 'center', gap: 8, fontSize: 11.5, color: T.primaryDark,
          }}>
            <Icon name="shieldCheck" size={16} color={T.primary}/>
            <span><b>Séquestre escrow</b> · fonds débloqués à la livraison.</span>
          </div>
        </div>
      </div>

      {/* Sticky CTA */}
      <div style={{ background: T.surface, borderTop: `1px solid ${T.line2}`, padding: '12px 16px', flexShrink: 0 }}>
        <Btn variant="primary" size="lg" full iconRight="arrowRight" onClick={() => nav('orders')}>
          Payer {total.toLocaleString('fr-FR')} FCFA
        </Btn>
      </div>
    </div>
  );
}

function SumRow({ l, v, bold, large }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', alignItems: 'baseline' }}>
      <span style={{ fontSize: large ? 14 : 12.5, color: bold ? T.ink : T.ink2, fontWeight: bold ? 700 : 500 }}>{l}</span>
      <span style={{ fontSize: large ? 17 : 13, fontWeight: bold ? 800 : 600, color: T.ink, fontFeatureSettings: '"tnum"' }}>{v}</span>
    </div>
  );
}

Object.assign(window, {
  SplashScreen, LoginScreen, HomeScreen, CatalogScreen, ProductScreen, CartScreen, Section, Field, SumRow,
});
