<script>
  import { listBooks } from '../lib/api';
  import BookCard from './BookCard.svelte';
  import { onMount } from 'svelte';

  export let libraryName;
  export let libraryId;

  let query = "";
  let loading = false;
  let books = [];
  let error = null;

  async function fetchBooks() {
    console.log(`[catalog] Fetching books for ${libraryId} with query: "${query}"`);
    
    // Clear state
    books = [];
    error = null;
    loading = true;
    
    try {
      const res = await listBooks(libraryId, query);
      console.log(`[catalog] Received ${res.books?.length || 0} books`);
      books = res.books || [];
      if (books.length === 0) {
        error = "No books found in this category.";
      }
    } catch (e) {
      console.error(`[catalog] Error fetching books:`, e);
      error = `Failed to load catalog: ${e.message}`;
    } finally {
      loading = false;
    }
  }

  // Initial fetch on mount
  onMount(() => {
    fetchBooks();
  });

  function handleKeydown(e) {
    if (e.key === 'Enter') fetchBooks();
  }
</script>

<div class="hero" style="padding-bottom: 20px;">
  <h1>{libraryName} Catalog</h1>
  <p>Browse and search books specifically in the {libraryName}.</p>
</div>

<div class="search-wrap" style="margin-bottom: 10px;">
  <input
    type="text"
    class="search-box"
    placeholder="Search by title or author..."
    bind:value={query}
    on:keydown={handleKeydown}
  />
</div>

<div class="search-footer" style="margin-bottom: 30px; justify-content: flex-end;">
  <button class="search-btn" on:click={fetchBooks}>Search</button>
</div>

{#if loading}
  <div class="thinking" style="flex-direction: column;">
    <div style="display: flex; gap: 0.5rem;">
    </div>
    <span style="font-family: 'DM Mono', monospace; font-size: 0.75rem; color: var(--accent); margin-top: 1rem;">System is working...</span>
  </div>
{/if}

{#if error && !loading}
  <div style="color: var(--muted); text-align: center; margin: 3rem 0; font-style: italic;">
    {error}
  </div>
{/if}

<div id="results">
  {#if !loading}
    {#each books as book}
      <BookCard {book} />
    {/each}
  {/if}
</div>
