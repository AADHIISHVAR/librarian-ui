<script>
  import { advancedSearch } from '../lib/api';
  import BookCard from './BookCard.svelte';

  let title = "";
  let author = "";
  let isbn = "";
  let acc_no = "";
  
  let loading = false;
  let books = [];
  let error = null;

  async function handleSearch() {
    if (!title && !author && !isbn && !acc_no) {
      error = "Please enter at least one search criteria.";
      return;
    }

    console.log(`[advanced] Searching with title="${title}", author="${author}", isbn="${isbn}", acc_no="${acc_no}"`);
    loading = true;
    error = null;
    try {
      const res = await advancedSearch({
        title: title || null,
        author: author || null,
        isbn: isbn || null,
        acc_no: acc_no || null
      });
      books = res.books || [];
      if (books.length === 0) {
        error = "No books found matching your criteria.";
      }
    } catch (e) {
      console.error(`[advanced] Error:`, e);
      error = `Search failed: ${e.message}`;
      books = [];
    } finally {
      loading = false;
    }
  }

  function clearForm() {
    title = "";
    author = "";
    isbn = "";
    acc_no = "";
    books = [];
    error = null;
  }

  function handleKeydown(e) {
    if (e.key === 'Enter') handleSearch();
  }
</script>

<div class="hero">
  <h1>Advanced Search</h1>
  <p>Search across the full combined library database with specific filters.</p>
</div>

<div class="advanced-form">
  <div class="input-grid">
    <div class="input-group">
      <label for="title">Book Title</label>
      <input
        id="title"
        type="text"
        placeholder="Enter title keyword..."
        bind:value={title}
        on:keydown={handleKeydown}
      />
    </div>
    <div class="input-group">
      <label for="author">Author Name</label>
      <input
        id="author"
        type="text"
        placeholder="Enter author name..."
        bind:value={author}
        on:keydown={handleKeydown}
      />
    </div>
    <div class="input-group">
      <label for="isbn">ISBN Number</label>
      <input
        id="isbn"
        type="text"
        placeholder="e.g. 978..."
        bind:value={isbn}
        on:keydown={handleKeydown}
      />
    </div>
    <div class="input-group">
      <label for="acc_no">Accession Number</label>
      <input
        id="acc_no"
        type="text"
        placeholder="e.g. 12345"
        bind:value={acc_no}
        on:keydown={handleKeydown}
      />
    </div>
  </div>

  <div class="form-actions">
    <button class="clear-btn" on:click={clearForm}>Clear</button>
    <button class="search-btn" on:click={handleSearch}>Search Database</button>
  </div>
</div>

{#if loading}
  <div class="thinking">
    <div class="dot"></div>
    <div class="dot" style="animation-delay: 0.2s"></div>
    <div class="dot" style="animation-delay: 0.4s"></div>
  </div>
{/if}

{#if error && !loading}
  <div style="color: var(--muted); text-align: center; margin: 3rem 0; font-style: italic;">
    {error}
  </div>
{/if}

<div id="results">
  {#each books as book}
    <BookCard {book} />
  {/each}
</div>

<style>
  .advanced-form {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.05);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 2rem;
  }

  .input-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
    margin-bottom: 1.5rem;
  }

  @media (max-width: 600px) {
    .input-grid {
      grid-template-columns: 1fr;
    }
  }

  .input-group {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  label {
    font-size: 0.8rem;
    color: var(--muted);
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  input {
    background: rgba(0, 0, 0, 0.2);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    padding: 0.8rem 1rem;
    color: var(--text);
    font-size: 1rem;
    transition: all 0.2s;
  }

  input:focus {
    outline: none;
    border-color: var(--accent);
    background: rgba(0, 0, 0, 0.3);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: 1rem;
    margin-top: 1rem;
  }

  .clear-btn {
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: var(--muted);
    padding: 0.75rem 1.5rem;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 500;
    transition: all 0.2s;
  }

  .clear-btn:hover {
    background: rgba(255, 255, 255, 0.05);
    color: var(--text);
  }

  .search-btn {
    background: var(--accent);
    color: #1a1409;
    border: none;
    padding: 0.75rem 2rem;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    transition: all 0.2s;
  }

  .search-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(200, 169, 110, 0.3);
  }
</style>
