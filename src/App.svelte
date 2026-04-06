<script>
  import AISearchView from './components/AISearchView.svelte';
  import LibraryListView from './components/LibraryListView.svelte';

  let activeTab = 'AI';

  const tabs = [
    { id: 'AI', label: 'AI Search' },
    { id: 'Central', label: 'Central' },
    { id: 'MBA', label: 'MBA / KBS' },
    { id: 'Competitive', label: 'Competitive' }
  ];
</script>

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

<footer>LIBRARIAN AI · Beta v1.1 · COLLEGE LIBRARY SYSTEM</footer>
