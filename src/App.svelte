<script>
  import AISearchView from './components/AISearchView.svelte';
  import LibraryListView from './components/LibraryListView.svelte';
  import AdvancedSearchView from './components/AdvancedSearchView.svelte';
  import AdminLoginView from './components/AdminLoginView.svelte';
  import NeuralyzerView from './components/NeuralyzerView.svelte';

  let activeTab = 'AI';
  let showBetaNotice = true;
  let showMenu = false;
  let currentView = 'Main'; // 'Main' | 'Admin' | 'Neuralyzer'

  function dismissNotice() {
    showBetaNotice = false;
  }

  function toggleMenu() {
    showMenu = !showMenu;
  }

  function setView(view) {
    currentView = view;
    showMenu = false;
  }

  const tabs = [
    { id: 'AI', label: 'AI Search' },
    { id: 'Central', label: 'Central' },
    { id: 'MBA', label: 'MBA / KBS' },
    { id: 'Competitive', label: 'Competitive' },
    { id: 'Advanced', label: 'Advanced' }
  ];
</script>

{#if showBetaNotice}
  <div class="beta-banner">
    <div class="beta-content">
      <span class="beta-icon">i</span>
      <p>
        <strong>Developer Note:</strong> This application is in beta version, not all the data will be available, we(I) are working on it and the updated pipeline will be pushed to production sooner.
      </p>
      <button class="beta-close" on:click={dismissNotice} aria-label="Dismiss notice">×</button>
    </div>
  </div>
{/if}

<header>
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <!-- svelte-ignore a11y-no-static-element-interactions -->
  <div class="logo" on:click={() => setView('Main')} style="cursor: pointer;">
    <span class="logo-name">Librarian</span>
    <span class="logo-tag">Beta v1.2</span>
  </div>
  
  <div class="header-center">
    {#if currentView === 'Main'}
      <div class="lib-switcher-wrap">
        <div class="lib-switcher">
          {#each tabs as tab}
            <button 
              class="lib-btn" 
              class:active={activeTab === tab.id}
              on:click={() => activeTab = tab.id}
            >
              {tab.label}
            </button>
          {/each}
        </div>
        <div class="scroll-arrow">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
            <path d="M9 18l6-6-6-6"/>
          </svg>
        </div>
      </div>
    {/if}
  </div>

  <div class="header-right">
    <div class="menu-container">
      <button class="hamburger-btn" on:click={toggleMenu} aria-label="Menu">
        <div class="bar"></div>
        <div class="bar"></div>
        <div class="bar"></div>
      </button>

      {#if showMenu}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <!-- svelte-ignore a11y-no-static-element-interactions -->
        <div class="menu-dropdown">
          <div class="menu-item" on:click={() => setView('Admin')}>
            <span class="menu-icon">👤</span> Admin Login
          </div>
          <div class="menu-item" on:click={() => setView('Neuralyzer')}>
            <span class="menu-icon">✨</span> The Flashy Thingy
          </div>
          {#if currentView !== 'Main'}
            <div class="menu-item divider-top" on:click={() => setView('Main')}>
              <span class="menu-icon">🏠</span> Back to Search
            </div>
          {/if}
        </div>
      {/if}
    </div>
  </div>
</header>

<main>
  {#if currentView === 'Admin'}
    <AdminLoginView />
  {:else if currentView === 'Neuralyzer'}
    <NeuralyzerView />
  {:else}
    {#if activeTab === 'AI'}
      <AISearchView />
    {:else if activeTab === 'Central'}
      <LibraryListView libraryName="Central" libraryId="Central" />
    {:else if activeTab === 'MBA'}
      <LibraryListView libraryName="MBA" libraryId="MBA" />
    {:else if activeTab === 'Competitive'}
      <LibraryListView libraryName="Competitive & Entrance" libraryId="Competitive" />
    {:else if activeTab === 'Advanced'}
      <AdvancedSearchView />
    {/if}
  {/if}
</main>

<style>
  .beta-banner {
    background: rgba(200, 169, 110, 0.1);
    border-bottom: 1px solid rgba(200, 169, 110, 0.2);
    padding: 0.75rem 1rem;
    position: relative;
    z-index: 90;
    animation: slideDown 0.4s ease-out;
  }

  .beta-content {
    max-width: 820px;
    margin: 0 auto;
    display: flex;
    align-items: center;
    gap: 1rem;
    position: relative;
    padding-right: 2rem;
  }

  .beta-icon {
    background: var(--accent);
    color: #1a1409;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-weight: bold;
    flex-shrink: 0;
  }

  .beta-content p {
    font-size: 0.85rem;
    color: var(--text);
    line-height: 1.4;
    margin: 0;
  }

  .beta-content strong {
    color: var(--accent);
    font-weight: 600;
  }

  .beta-close {
    position: absolute;
    right: 0;
    top: 50%;
    transform: translateY(-50%);
    background: none;
    border: none;
    color: var(--muted);
    font-size: 1.5rem;
    cursor: pointer;
    line-height: 1;
    padding: 0.2rem;
    transition: color 0.2s;
  }

  .beta-close:hover {
    color: var(--accent);
  }

  @keyframes slideDown {
    from { transform: translateY(-100%); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
  }

  @media (max-width: 600px) {
    .beta-content {
      gap: 0.75rem;
    }
    .beta-content p {
      font-size: 0.75rem;
    }
  }

  /* Hamburger Menu Styles */
  .header-right {
    display: flex;
    justify-content: flex-end;
    flex: 1;
  }

  .menu-container {
    position: relative;
  }

  .hamburger-btn {
    background: none;
    border: none;
    cursor: pointer;
    padding: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 4px;
    z-index: 110;
  }

  .bar {
    width: 20px;
    height: 2px;
    background-color: var(--accent);
    border-radius: 2px;
    transition: 0.3s;
  }

  .menu-dropdown {
    position: absolute;
    top: calc(100% + 10px);
    right: 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 0.5rem;
    width: 200px;
    box-shadow: 0 10px 25px rgba(0,0,0,0.5);
    z-index: 105;
    animation: fadeIn 0.2s ease-out;
  }

  .menu-item {
    padding: 0.75rem 1rem;
    color: var(--text);
    font-size: 0.9rem;
    cursor: pointer;
    border-radius: 8px;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    transition: background 0.2s;
  }

  .menu-item:hover {
    background: rgba(255, 255, 255, 0.05);
    color: var(--accent);
  }

  .menu-icon {
    font-size: 1.1rem;
  }

  .divider-top {
    border-top: 1px solid var(--border);
    margin-top: 0.5rem;
    padding-top: 1rem;
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(-10px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>


<footer>LIBRARIAN AI · Beta v1.2 · COLLEGE LIBRARY SYSTEM</footer>
