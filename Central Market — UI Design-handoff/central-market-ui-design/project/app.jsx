/*
 * Marché CM — App shell with 4 roles + 5th "Extras" group
 * (Acheteur / Vendeur / Livreur / Admin) + Onboarding KYC, Notifs, Logo lab, Litige multi-vue
 */

function App() {
  const [role, setRole] = React.useState('buyer');

  const [buyerStack, setBuyerStack] = React.useState(['splash']);
  const [vendorStack, setVendorStack] = React.useState(['v-dashboard']);
  const [livreurStack, setLivreurStack] = React.useState(['l-dashboard']);
  const [adminStack, setAdminStack] = React.useState(['a-dashboard']);
  const [extrasStack, setExtrasStack] = React.useState(['kyc-intro']);
  const [livreurType, setLivreurType] = React.useState('individual');

  const stacks = {
    buyer:   [buyerStack, setBuyerStack],
    vendor:  [vendorStack, setVendorStack],
    livreur: [livreurStack, setLivreurStack],
    admin:   [adminStack, setAdminStack],
    extras:  [extrasStack, setExtrasStack],
  };
  const [stack, setStack] = stacks[role];
  const current = stack[stack.length - 1];

  const nav = React.useCallback((to) => setStack(s => [...s, to]), [setStack]);
  const jump = React.useCallback((to) => setStack([to]), [setStack]);
  const switchRole = (next) => setRole(next);

  const BUYER_SCREENS = {
    'splash':       () => <SplashScreen nav={jump}/>,
    'login':        () => <LoginScreen nav={jump}/>,
    'home':         () => <HomeScreen nav={nav}/>,
    'catalog':      () => <CatalogScreen nav={nav}/>,
    'product':      () => <ProductScreen nav={nav}/>,
    'cart':         () => <CartScreen nav={nav}/>,
    'wallet':       () => <WalletScreen nav={nav}/>,
    'topup':        () => <TopupScreen nav={nav}/>,
    'orders':       () => <OrdersScreen nav={nav}/>,
    'tracking':     () => <TrackingScreen nav={nav}/>,
    'chat-list':    () => <ChatListScreen nav={nav}/>,
    'chat-thread':  () => <ChatThreadScreen nav={nav}/>,
    'profile':      () => <ProfileScreen nav={nav}/>,
  };
  const VENDOR_SCREENS = {
    'v-dashboard':     () => <VDashboardScreen nav={nav}/>,
    'v-products':      () => <VProductsScreen nav={nav}/>,
    'v-product-edit':  () => <VProductEditScreen nav={nav}/>,
    'v-orders':        () => <VOrdersScreen nav={nav}/>,
    'v-order-detail':  () => <VOrderDetailScreen nav={nav}/>,
    'v-earnings':      () => <VEarningsScreen nav={nav}/>,
    'v-stats':         () => <VStatsScreen nav={nav}/>,
    'v-rfq':           () => <VRfqScreen nav={nav}/>,
    'v-profile':       () => <VProfileScreen nav={nav} onSwitchRole={() => switchRole('buyer')}/>,
    'chat-list':       () => <ChatListScreen nav={nav}/>,
    'chat-thread':     () => <ChatThreadScreen nav={nav}/>,
  };
  const LIVREUR_SCREENS = {
    'l-dashboard':       () => <LDashboardScreen nav={nav} profileType={livreurType}/>,
    'l-bids':            () => <LBidsScreen nav={nav}/>,
    'l-quote':           () => <LQuoteScreen nav={nav}/>,
    'l-shipments':       () => <LShipmentsScreen nav={nav}/>,
    'l-shipment-detail': () => <LShipmentDetailScreen nav={nav}/>,
    'l-proof':           () => <LProofScreen nav={nav}/>,
    'l-earnings':        () => <LEarningsScreen nav={nav}/>,
    'l-reviews':         () => <LReviewsScreen nav={nav}/>,
    'l-profile':         () => <LProfileScreen nav={nav} profileType={livreurType} setProfileType={setLivreurType} onSwitchRole={() => switchRole('buyer')}/>,
    'chat-list':         () => <ChatListScreen nav={nav}/>,
    'chat-thread':       () => <ChatThreadScreen nav={nav}/>,
  };
  const ADMIN_SCREENS = {
    'a-dashboard':       () => <ADashboardScreen nav={nav}/>,
    'a-users':           () => <AUsersScreen nav={nav}/>,
    'a-user-detail':     () => <AUserDetailScreen nav={nav}/>,
    'a-kyc':             () => <AKycScreen nav={nav}/>,
    'a-kyc-review':      () => <AKycReviewScreen nav={nav}/>,
    'a-disputes':        () => <ADisputesScreen nav={nav}/>,
    'a-dispute-detail':  () => <ADisputeDetailScreen nav={nav}/>,
    'a-reconcile':       () => <AReconcileScreen nav={nav}/>,
    'a-audit':           () => <AAuditScreen nav={nav}/>,
    'a-config':          () => <AConfigScreen nav={nav}/>,
    'a-profile':         () => <AProfileScreen nav={nav} onSwitchRole={() => switchRole('buyer')}/>,
  };
  const EXTRAS_SCREENS = {
    // KYC flow
    'kyc-intro':         () => <KycIntroScreen nav={nav}/>,
    'kyc-type':          () => <KycTypeScreen nav={nav}/>,
    'kyc-docs':          () => <KycDocsScreen nav={nav}/>,
    'kyc-signature':     () => <KycSignatureScreen nav={nav}/>,
    'kyc-review':        () => <KycReviewScreen nav={nav}/>,
    'kyc-success':       () => <KycSuccessScreen nav={nav}/>,
    'home':              () => <HomeScreen nav={nav}/>,
    // Notifications
    'notifications':     () => <NotificationsScreen nav={nav}/>,
    // Logo lab
    'logo-lab':          () => <LogoLabScreen nav={nav}/>,
    // Multi-view dispute
    'dispute-hub':       () => <DisputeHubScreen nav={nav}/>,
    'dispute-buyer':     () => <DisputeBuyerScreen nav={nav}/>,
    'dispute-vendor':    () => <DisputeVendorScreen nav={nav}/>,
    'dispute-livreur':   () => <DisputeLivreurScreen nav={nav}/>,
    'dispute-arbitre':   () => <DisputeArbitreScreen nav={nav}/>,
  };

  const SCREENS = role === 'buyer'   ? BUYER_SCREENS
                 : role === 'vendor'  ? VENDOR_SCREENS
                 : role === 'livreur' ? LIVREUR_SCREENS
                 : role === 'admin'   ? ADMIN_SCREENS
                 :                       EXTRAS_SCREENS;

  // Tab routing
  let activeTab = null, showTabs = false;
  if (role === 'buyer') {
    const map = {
      'home': 'home', 'catalog': 'catalog', 'product': 'catalog',
      'wallet': 'wallet', 'topup': 'wallet',
      'orders': 'orders', 'tracking': 'orders',
      'profile': 'profile',
      'chat-list': 'chat-list', 'chat-thread': 'chat-list',
    };
    activeTab = map[current] || null;
    showTabs = ['home','catalog','wallet','orders','profile','chat-list'].includes(current);
  } else if (role === 'vendor') {
    const map = {
      'v-dashboard': 'v-dashboard',
      'v-products': 'v-products', 'v-product-edit': 'v-products',
      'v-orders': 'v-orders', 'v-order-detail': 'v-orders',
      'v-stats': 'v-stats', 'v-earnings': 'v-stats',
      'v-profile': 'v-profile', 'v-rfq': 'v-dashboard',
    };
    activeTab = map[current] || null;
    showTabs = ['v-dashboard','v-products','v-orders','v-stats','v-profile'].includes(current);
  } else if (role === 'livreur') {
    const map = {
      'l-dashboard': 'l-dashboard',
      'l-bids': 'l-bids', 'l-quote': 'l-bids',
      'l-shipments': 'l-shipments', 'l-shipment-detail': 'l-shipments', 'l-proof': 'l-shipments',
      'l-earnings': 'l-earnings',
      'l-profile': 'l-profile', 'l-reviews': 'l-profile',
    };
    activeTab = map[current] || null;
    showTabs = ['l-dashboard','l-bids','l-shipments','l-earnings','l-profile'].includes(current);
  } else if (role === 'admin') {
    const map = {
      'a-dashboard': 'a-dashboard',
      'a-users': 'a-users', 'a-user-detail': 'a-users', 'a-kyc': 'a-users', 'a-kyc-review': 'a-users',
      'a-disputes': 'a-disputes', 'a-dispute-detail': 'a-disputes',
      'a-reconcile': 'a-reconcile', 'a-audit': 'a-reconcile',
      'a-config': 'a-profile', 'a-profile': 'a-profile',
    };
    activeTab = map[current] || null;
    showTabs = ['a-dashboard','a-users','a-disputes','a-reconcile','a-profile'].includes(current);
  }

  // Status bar styling
  const darkStatusScreens = new Set([
    'splash','login','profile',
    'v-dashboard','v-profile','v-earnings',
    'l-dashboard','l-profile','l-earnings','l-shipment-detail',
    'a-dashboard','a-user-detail','a-profile','a-reconcile',
    'kyc-success',
  ]);
  const darkStatus = darkStatusScreens.has(current);
  const statusBg = current === 'splash' ? 'transparent' :
                   ['login','profile','v-profile','v-dashboard','v-earnings','a-user-detail','kyc-success'].includes(current) ? T.primaryDeep :
                   ['l-profile','l-dashboard','l-earnings'].includes(current) ? '#8E5A00' :
                   ['a-dashboard','a-profile','a-reconcile'].includes(current) ? '#0E1F18' :
                   current === 'l-shipment-detail' ? '#E6F2EC' :
                   T.bg;

  return (
    <div style={{
      minHeight: '100vh',
      background: 'radial-gradient(120% 100% at 50% 0%, #F2EFE3 0%, #E6E0CC 100%)',
      padding: '24px 16px 32px',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      gap: 20, fontFamily: T.fontDisplay,
    }}>
      <div style={{
        width: '100%', maxWidth: 1180, display: 'flex',
        alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 16,
      }}>
        <Logo size={38} withWordmark/>
        <RoleSwitch role={role} onChange={switchRole}/>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
          <Pill variant="success"><Icon name="check" size={11} color={T.primaryDark} strokeWidth={3}/> UI/UX Pro Max</Pill>
          <Pill variant="warn">
            {role === 'buyer' ? '13' : role === 'vendor' ? '9' : role === 'livreur' ? '9' : role === 'admin' ? '11' : '15'} écrans
          </Pill>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 24, alignItems: 'flex-start', flexWrap: 'wrap', justifyContent: 'center' }}>
        <div style={{ position: 'relative' }}>
          <PhoneFrame statusBg={statusBg} darkStatus={darkStatus}>
            <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
              <div key={`${role}-${current}-${stack.length}`} style={{
                flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0,
                animation: `slideIn ${T.durationMd} ${T.easeOut}`,
              }}>
                {SCREENS[current] ? SCREENS[current]() : <div style={{ padding: 20 }}>Écran « {current} » introuvable.</div>}
              </div>

              {showTabs && role === 'buyer' && (
                <BottomNav active={activeTab} onNavigate={(id) => {
                  const tabMap = { home: 'home', catalog: 'catalog', wallet: 'wallet', orders: 'orders', profile: 'profile' };
                  jump(tabMap[id]);
                }}/>
              )}
              {showTabs && role === 'vendor' && <VBottomNav active={activeTab} onNavigate={(id) => jump(id)}/>}
              {showTabs && role === 'livreur' && <LBottomNav active={activeTab} onNavigate={(id) => jump(id)}/>}
              {showTabs && role === 'admin' && <ABottomNav active={activeTab} onNavigate={(id) => jump(id)}/>}
            </div>
          </PhoneFrame>

          {!['splash', 'login', 'chat-list', 'chat-thread', 'kyc-success', 'dispute-arbitre'].includes(current) && role !== 'admin' && role !== 'extras' && (
            <button onClick={() => nav('chat-list')} style={{
              position: 'absolute', right: -8, bottom: showTabs ? 100 : 36,
              width: 52, height: 52, borderRadius: '50%',
              background: T.ink, color: '#fff', border: `3px solid #EFEAD9`,
              cursor: 'pointer', display: 'grid', placeItems: 'center',
              boxShadow: T.shadowLg, zIndex: 5,
            }}>
              <Icon name="chat" size={20}/>
            </button>
          )}
        </div>

        <ScreenIndex role={role} current={current} onJump={jump}/>
      </div>

      <style>{`
        @keyframes slideIn {
          0% { opacity: 0; transform: translateX(8px); }
          100% { opacity: 1; transform: translateX(0); }
        }
        * { -webkit-tap-highlight-color: transparent; }
        button:focus-visible { outline: 2px solid ${T.primary}; outline-offset: 2px; }
        input:focus-visible { outline: none; }
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-thumb { background: rgba(0,0,0,.15); border-radius: 3px; }
        ::-webkit-scrollbar-track { background: transparent; }
      `}</style>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Role switcher — 5 modes
// ─────────────────────────────────────────────────────────────
function RoleSwitch({ role, onChange }) {
  const items = [
    { id: 'buyer',   label: 'Acheteur', icon: 'bag' },
    { id: 'vendor',  label: 'Vendeur',  icon: 'package' },
    { id: 'livreur', label: 'Livreur',  icon: 'truck' },
    { id: 'admin',   label: 'Admin',    icon: 'shield' },
    { id: 'extras',  label: 'Extras',   icon: 'star' },
  ];
  return (
    <div style={{
      display: 'inline-flex', background: '#fff',
      padding: 4, borderRadius: 14,
      border: `1px solid ${T.line}`, boxShadow: T.shadowSm,
      gap: 2, flexWrap: 'wrap',
    }}>
      {items.map(r => {
        const active = role === r.id;
        return (
          <button key={r.id} onClick={() => onChange(r.id)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '8px 12px', border: 'none', cursor: 'pointer',
            background: active ? T.ink : 'transparent',
            color: active ? '#fff' : T.ink2,
            borderRadius: 10, fontWeight: 700, fontSize: 12.5,
            fontFamily: T.fontDisplay,
            transition: `all ${T.duration} ${T.ease}`,
            minHeight: 38,
          }}>
            <Icon name={r.icon} size={14}/>
            {r.label}
          </button>
        );
      })}
    </div>
  );
}

function PhoneFrame({ children, statusBg, darkStatus }) {
  return (
    <div style={{
      width: 392, height: 820, borderRadius: 48, padding: 10,
      background: 'linear-gradient(155deg, #2A2A2E 0%, #0E0E12 100%)',
      boxShadow: '0 40px 80px -20px rgba(0,0,0,.45), 0 12px 24px -8px rgba(0,0,0,.25), inset 0 2px 4px rgba(255,255,255,.05)',
      position: 'relative',
    }}>
      <div style={{ position: 'absolute', right: -2, top: 180, width: 4, height: 80, background: '#2A2A2E', borderRadius: '0 2px 2px 0' }}/>
      <div style={{ position: 'absolute', left: -2, top: 150, width: 4, height: 50, background: '#2A2A2E', borderRadius: '2px 0 0 2px' }}/>
      <div style={{ position: 'absolute', left: -2, top: 220, width: 4, height: 50, background: '#2A2A2E', borderRadius: '2px 0 0 2px' }}/>

      <div style={{
        width: '100%', height: '100%', borderRadius: 38,
        overflow: 'hidden', background: statusBg || T.bg,
        display: 'flex', flexDirection: 'column', position: 'relative',
      }}>
        <StatusBar dark={darkStatus} bg={statusBg}/>
        <div style={{
          position: 'absolute', left: '50%', top: 10, transform: 'translateX(-50%)',
          width: 100, height: 28, borderRadius: 14, background: '#0a0a0a', zIndex: 100,
        }}/>
        {children}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '8px 0 10px', flexShrink: 0, background: 'inherit' }}>
          <div style={{
            width: 120, height: 4, borderRadius: 2,
            background: darkStatus ? 'rgba(255,255,255,.5)' : 'rgba(14,31,24,.4)',
          }}/>
        </div>
      </div>
    </div>
  );
}

// Screen index data
const BUYER_INDEX = [
  { id: 'splash',       label: '01 · Splash',     sub: 'Logo brand intro',     icon: 'mountain' },
  { id: 'login',        label: '02 · Login',      sub: 'Email + Google + OTP', icon: 'lock' },
  { id: 'home',         label: '03 · Accueil',    sub: 'Wallet · catégories',  icon: 'home' },
  { id: 'catalog',      label: '04 · Catalogue',  sub: 'Recherche + filtres',  icon: 'search' },
  { id: 'product',      label: '05 · Produit',    sub: 'Pricing tiers B2B',    icon: 'package' },
  { id: 'cart',         label: '06 · Panier',     sub: 'Choix transitaire',    icon: 'bag' },
  { id: 'wallet',       label: '07 · Wallet',     sub: 'Solde + escrow',       icon: 'wallet' },
  { id: 'topup',        label: '08 · Recharge',   sub: 'MoMo / OM / Carte',    icon: 'plus' },
  { id: 'orders',       label: '09 · Commandes',  sub: 'En cours · livrées',   icon: 'package' },
  { id: 'tracking',     label: '10 · Suivi',      sub: 'Timeline transitaire', icon: 'truck' },
  { id: 'chat-list',    label: '11 · Messagerie', sub: 'Conversations',        icon: 'chat' },
  { id: 'chat-thread',  label: '12 · Discussion', sub: 'Devis transitaire',    icon: 'send' },
  { id: 'profile',      label: '13 · Profil',     sub: 'KYC + paramètres',     icon: 'user' },
];
const VENDOR_INDEX = [
  { id: 'v-dashboard',    label: '01 · Tableau de bord', sub: 'CA · alertes · KPI',     icon: 'home' },
  { id: 'v-products',     label: '02 · Mes produits',    sub: 'Catalogue · stock',      icon: 'package' },
  { id: 'v-product-edit', label: '03 · Éditer produit',  sub: 'Photos · paliers B2B',   icon: 'edit' },
  { id: 'v-orders',       label: '04 · Commandes reçues',sub: 'À préparer · expédiées', icon: 'bag' },
  { id: 'v-order-detail', label: '05 · Détail commande', sub: 'Stepper séquestre',      icon: 'shield' },
  { id: 'v-rfq',          label: '06 · RFQ entrantes',   sub: 'Demandes de devis',      icon: 'scale' },
  { id: 'v-earnings',     label: '07 · Revenus',         sub: 'Retraits · escrow',      icon: 'wallet' },
  { id: 'v-stats',        label: '08 · Statistiques',    sub: 'CA · top produits',      icon: 'trending' },
  { id: 'v-profile',      label: '09 · Profil vendeur',  sub: 'KYC · vitrine',          icon: 'user' },
];
const LIVREUR_INDEX = [
  { id: 'l-dashboard',       label: '01 · Tableau de bord', sub: 'En ligne · gains du jour', icon: 'home' },
  { id: 'l-bids',            label: '02 · Demandes',        sub: 'Expéditions ouvertes',     icon: 'scale' },
  { id: 'l-quote',           label: '03 · Envoyer devis',   sub: 'Prix · ETA · véhicule',    icon: 'send' },
  { id: 'l-shipments',       label: '04 · Mes courses',     sub: 'Devis · en cours',         icon: 'truck' },
  { id: 'l-shipment-detail', label: '05 · Détail expédition', sub: 'Carte + stepper',        icon: 'mapPin' },
  { id: 'l-proof',           label: '06 · Preuve livraison',sub: 'Photo + code 4 chiffres',  icon: 'camera' },
  { id: 'l-earnings',        label: '07 · Gains',           sub: 'Retraits MoMo',            icon: 'wallet' },
  { id: 'l-reviews',         label: '08 · Avis',            sub: '218 évaluations',          icon: 'star' },
  { id: 'l-profile',         label: '09 · Profil livreur',  sub: 'Individuel ↔ Entreprise',  icon: 'user' },
];
const ADMIN_INDEX = [
  { id: 'a-dashboard',      label: '01 · Tableau de bord',  sub: 'GMV · alertes critiques',  icon: 'home' },
  { id: 'a-users',          label: '02 · Utilisateurs',     sub: '12 480 comptes',           icon: 'user' },
  { id: 'a-user-detail',    label: '03 · Fiche utilisateur',sub: 'KYC · audit · actions',    icon: 'shieldCheck' },
  { id: 'a-kyc',            label: '04 · Conformité KYC',   sub: '14 en attente',            icon: 'shield' },
  { id: 'a-kyc-review',     label: '05 · Revue document',   sub: 'Checklist + commentaire',  icon: 'edit' },
  { id: 'a-disputes',       label: '06 · Litiges',          sub: '6 ouverts · 2 urgents',    icon: 'flag' },
  { id: 'a-dispute-detail', label: '07 · Arbitrage',        sub: 'Décision séquestre',       icon: 'scale' },
  { id: 'a-reconcile',      label: '08 · Réconciliation',   sub: 'NotchPay vs système',      icon: 'wallet' },
  { id: 'a-audit',          label: '09 · Audit & journaux', sub: 'Export CSV',               icon: 'list' },
  { id: 'a-config',         label: '10 · Configuration',    sub: 'Commissions · sécurité',   icon: 'edit' },
  { id: 'a-profile',        label: '11 · Profil admin',     sub: 'Permissions · 2FA',        icon: 'user' },
];
const EXTRAS_INDEX = [
  // KYC Onboarding (partagé)
  { id: 'kyc-intro',       label: '01 · KYC · Intro',       sub: 'Pré-requis · sécurité',    icon: 'shield', group: 'KYC' },
  { id: 'kyc-type',        label: '02 · KYC · Type compte', sub: 'Particulier · SARL · pro', icon: 'user', group: 'KYC' },
  { id: 'kyc-docs',        label: '03 · KYC · Documents',   sub: 'CNI · domicile · selfie',  icon: 'camera', group: 'KYC' },
  { id: 'kyc-signature',   label: '04 · KYC · Signature',   sub: 'Signature manuscrite',     icon: 'edit', group: 'KYC' },
  { id: 'kyc-review',      label: '05 · KYC · Récap',       sub: 'Vérification avant envoi', icon: 'list', group: 'KYC' },
  { id: 'kyc-success',     label: '06 · KYC · Succès',      sub: 'Dossier envoyé',           icon: 'check', group: 'KYC' },
  // Notifications
  { id: 'notifications',   label: '07 · Notifications',     sub: 'Inbox multi-domaines',     icon: 'bell', group: 'Notifs' },
  // Logo lab
  { id: 'logo-lab',        label: '08 · Variantes logo',    sub: '4 directions de marque',   icon: 'star', group: 'Brand' },
  // Dispute multi-view
  { id: 'dispute-hub',     label: '09 · Litige · Hub',      sub: 'Choisir une perspective',  icon: 'flag', group: 'Litige' },
  { id: 'dispute-buyer',   label: '10 · Litige · Acheteur', sub: 'Vue plaignante',           icon: 'bag', group: 'Litige' },
  { id: 'dispute-vendor',  label: '11 · Litige · Vendeur',  sub: 'Vue témoin',               icon: 'package', group: 'Litige' },
  { id: 'dispute-livreur', label: '12 · Litige · Livreur',  sub: 'Vue mis en cause',         icon: 'truck', group: 'Litige' },
  { id: 'dispute-arbitre', label: '13 · Litige · Arbitre',  sub: 'Chat tripartite + admin',  icon: 'chat', group: 'Litige' },
];

function ScreenIndex({ role, current, onJump }) {
  const screens = role === 'buyer'   ? BUYER_INDEX
                 : role === 'vendor'  ? VENDOR_INDEX
                 : role === 'livreur' ? LIVREUR_INDEX
                 : role === 'admin'   ? ADMIN_INDEX
                 :                       EXTRAS_INDEX;
  const title = role === 'buyer'   ? 'Flux acheteur'
              : role === 'vendor'  ? 'Flux vendeur'
              : role === 'livreur' ? 'Flux livreur'
              : role === 'admin'   ? 'Flux administrateur'
              :                       'Modules transverses';
  const note = role === 'buyer'
    ? 'Parcours B2B/B2C : du séquestre à la confirmation de livraison.'
    : role === 'vendor'
    ? 'Parcours Fournisseur / Grossiste.'
    : role === 'livreur'
    ? 'Parcours Transitaire (indépendant ou entreprise).'
    : role === 'admin'
    ? 'Gouvernance plateforme : KYC, litiges, réconciliation.'
    : 'Onboarding KYC, notifications, variantes logo, litige multi-vue.';
  const icon = role === 'buyer' ? 'bag' : role === 'vendor' ? 'package' : role === 'livreur' ? 'truck' : role === 'admin' ? 'shield' : 'star';

  // Group extras by section
  const grouped = role === 'extras' ? screens.reduce((acc, s) => {
    (acc[s.group] = acc[s.group] || []).push(s); return acc;
  }, {}) : null;

  return (
    <div style={{
      width: 290, background: T.surface, borderRadius: 24, padding: 14,
      border: `1px solid ${T.line}`, boxShadow: T.shadowMd,
      maxHeight: 820, display: 'flex', flexDirection: 'column',
    }}>
      <div style={{ padding: '6px 8px 10px', borderBottom: `1px solid ${T.line2}`, marginBottom: 6 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Icon name={icon} size={14} color={T.primary}/>
          <div style={{ fontSize: 11, fontWeight: 800, color: T.ink3, textTransform: 'uppercase', letterSpacing: '.08em' }}>{title}</div>
        </div>
        <div style={{ fontSize: 11.5, color: T.ink2, marginTop: 4, lineHeight: 1.45 }}>{note}</div>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 2 }}>
        {grouped ? Object.entries(grouped).map(([groupName, items]) => (
          <div key={groupName}>
            <div style={{
              fontSize: 10, fontWeight: 800, color: T.ink3,
              textTransform: 'uppercase', letterSpacing: '.1em',
              padding: '10px 10px 4px',
            }}>{groupName}</div>
            {items.map(s => renderScreenItem(s, current, onJump))}
          </div>
        )) : screens.map(s => renderScreenItem(s, current, onJump))}
      </div>
      <div style={{ padding: '10px 8px 4px', borderTop: `1px solid ${T.line2}`, marginTop: 6 }}>
        <div style={{ fontSize: 11, color: T.ink3, lineHeight: 1.5 }}>
          <b style={{ color: T.ink }}>Marché CM</b> — palette Cameroun, Mont Cameroun + étoile du drapeau.
        </div>
      </div>
    </div>
  );
}

function renderScreenItem(s, current, onJump) {
  const active = current === s.id;
  return (
    <button key={s.id} onClick={() => onJump(s.id)} style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '9px 10px', borderRadius: 10, border: 'none',
      background: active ? T.primarySoft : 'transparent',
      cursor: 'pointer', textAlign: 'left',
      transition: `background ${T.duration} ${T.ease}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8,
        background: active ? T.primary : T.surface2,
        color: active ? '#fff' : T.ink2,
        display: 'grid', placeItems: 'center', flexShrink: 0,
      }}>
        <Icon name={s.icon} size={15}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 12.5, fontWeight: 700,
          color: active ? T.primaryDark : T.ink,
          fontFamily: T.fontDisplay, letterSpacing: '-0.005em',
        }}>{s.label}</div>
        <div style={{ fontSize: 10.5, color: T.ink3, marginTop: 1 }}>{s.sub}</div>
      </div>
      {active && <Icon name="arrowRight" size={14} color={T.primary}/>}
    </button>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App/>);
