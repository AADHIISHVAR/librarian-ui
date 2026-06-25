<script>
  export let book;
  let showDetails = false;

  $: isMba = book.library.toLowerCase().includes("mba") || 
            book.library.toLowerCase().includes("kbs") ||
            book.dept.toLowerCase().includes("mba") ||
            book.subject.toLowerCase().includes("management");

  $: libLabel = isMba ? "MBA LIBRARY" : "GENERAL LIBRARY";
</script>

<div class="result-card">
  <div class="card-layout">
    {#if book.cover_url}
      <div class="cover-wrapper">
        <img src={book.cover_url} alt="Cover for {book.title}" class="book-cover" loading="lazy" />
      </div>
    {:else}
      <div class="cover-wrapper no-cover-bg">
        <span class="no-cover">No Cover</span>
      </div>
    {/if}
    
    <div class="card-content">
      <div class="card-title">{book.title}</div>
      
      <div style="display: flex; align-items: center; margin-top: 8px;">
        <span class="location-badge" class:mba={isMba}>
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" style="margin-right: 4px;">
            <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>
          </svg>
          {libLabel}
        </span>
        <span class="hint">{book.shelf}</span>
      </div>

      <div class="card-author">{book.author}</div>
      
      <div class="hint" style="margin-top: 10px; margin-bottom: 8px;">
        Status: {book.status} · Match: {Math.round(book.similarity * 100)}%
      </div>

      <div>
        <button class="filter-chip" on:click={() => showDetails = !showDetails}>
          {showDetails ? "Hide Details" : "Show Details"}
        </button>
      </div>
    </div>
  </div>

  {#if showDetails}
    <div class="details-grid">
      <div><strong>Price:</strong> {book.price}</div>
      <div><strong>Publisher:</strong> {book.publisher}</div>
      <div><strong>Year:</strong> {book.year}</div>
      <div><strong>ISBN:</strong> {book.isbn}</div>
      <div><strong>Dept:</strong> {book.dept}</div>
      <div><strong>Subject:</strong> {book.subject}</div>
      
      {#if book.cover_url}
        <div style="grid-column: 1 / -1; font-size: 0.75rem; word-break: break-all;">
          <strong>Cover Image:</strong> <a href={book.cover_url} target="_blank" rel="noreferrer" style="color: var(--accent);">{book.cover_url}</a>
        </div>
      {/if}
      
      <div style="grid-column: 1 / -1; margin-top: 10px; line-height: 1.5; color: var(--muted);">
        <strong>Description:</strong><br/>
        {book.description || "No description available."}
      </div>
    </div>
  {/if}
</div>

<style>
  .card-layout {
    display: flex;
    gap: 16px;
    align-items: flex-start;
  }

  .cover-wrapper {
    flex-shrink: 0;
    width: 76px;
    height: 114px;
    border-radius: 6px;
    overflow: hidden;
    border: 1px solid var(--border);
    display: flex;
    align-items: center;
    justify-content: center;
    background: #0f0f12;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
  }

  .book-cover {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .no-cover-bg {
    background: linear-gradient(135deg, #1b1b22, #131317);
  }

  .no-cover {
    font-family: 'DM Mono', monospace;
    font-size: 0.65rem;
    color: var(--muted);
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }

  .card-content {
    flex: 1;
    display: flex;
    flex-direction: column;
  }

  @media (max-width: 480px) {
    .card-layout {
      flex-direction: column;
      align-items: center;
      text-align: center;
    }
    
    .cover-wrapper {
      width: 90px;
      height: 135px;
    }
    
    .card-content {
      align-items: center;
    }
  }
</style>

