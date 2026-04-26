<script>
  import { search } from '../lib/api';
  import BookCard from './BookCard.svelte';

  let query = "";
  let loading = false;
  let response = null;
  let error = null;

  async function doSearch() {
    if (!query.trim()) return;
    
    // Clear previous results to ensure loading is visible
    response = null;
    error = null;
    loading = true;
    
    try {
      response = await search(query, "all");
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }

  function handleKeydown(e) {
    if (e.key === 'Enter' && !e.shift_key) {
      e.preventDefault();
      doSearch();
    }
  }
</script>

<div class="hero">
  <div class="beta-tag-wrapper">
    <span class="logo-tag" style="margin-bottom: 1rem; display: inline-block;">Beta Version</span>
  </div>
  <h1>What are you looking<br/>to <em>discover</em> today?</h1>
  <p>Describe a topic, a feeling, or what you're curious about — we'll find the right book.</p>
</div>

<div class="search-wrap">
  <textarea
    class="search-box"
    placeholder="e.g. 'I want to understand how human behaviour affects decision making...'"
    rows="1"
    bind:value={query}
    on:keydown={handleKeydown}
  ></textarea>
</div>

<div class="search-footer">
  <span class="hint">↵ Enter to search · AI Powered</span>
  <button class="search-btn" on:click={doSearch}>AI Search</button>
</div>

{#if loading}
  <div class="thinking">
    <div class="dot"></div>
    <div class="dot" style="animation-delay: 0.2s"></div>
    <div class="dot" style="animation-delay: 0.4s"></div>
  </div>
{/if}

{#if error}
  <div style="color: var(--danger); text-align: center; margin: 2rem 0;">{error}</div>
{/if}

{#if response && !loading}
  <div class="divider show">
    <div class="divider-line"></div>
    <div class="divider-label">AI Analysis</div>
    <div class="divider-line"></div>
  </div>
  
  <div class="ai-reply">{response.reply}</div>
  
  <div id="results">
    {#each response.books as book}
      <BookCard {book} />
    {/each}
  </div>
{/if}
