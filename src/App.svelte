<script>
  import AISearchView from './components/AISearchView.svelte';
  import LibraryListView from './components/LibraryListView.svelte';

  let activeTab = 'AI';
  let showBetaNotice = localStorage.getItem('beta-notice-dismissed') !== 'true';

  function dismissNotice() {
    showBetaNotice = false;
    localStorage.setItem('beta-notice-dismissed', 'true');
  }

  const tabs = [
    { id: 'AI', label: 'AI Search' },
    { id: 'Central', label: 'Central' },
    { id: 'MBA', label: 'MBA / KBS' },
    { id: 'Competitive', label: 'Competitive' }
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
  <div class="logo">
    <span class="logo-name">Librarian</span>
    <span class="logo-tag">Beta v1.1</span>
  </div>
  
  <div class="header-center">
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
  </div>

  <div class="header-right-placeholder"></div>
</header>

<main>
  {#if activeTab === 'AI'}
    <AISearchView />
  {:else if activeTab === 'Central'}
    <LibraryListView libraryName="Central" libraryId="Central" />
  {:else if activeTab === 'MBA'}
    <LibraryListView libraryName="MBA" libraryId="MBA" />
  {:else if activeTab === 'Competitive'}
    <LibraryListView libraryName="Competitive & Entrance" libraryId="Competitive" />
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
</style>


<footer>LIBRARIAN AI · Beta v1.1 · COLLEGE LIBRARY SYSTEM</footer>
