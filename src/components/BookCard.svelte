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
  
  <div class="hint" style="margin-top: 10px;">
    Status: {book.status} · Match: {Math.round(book.similarity * 100)}%
  </div>

  <button class="filter-chip" on:click={() => showDetails = !showDetails}>
    {showDetails ? "Hide Details" : "Show Details"}
  </button>

  {#if showDetails}
    <div class="details-grid">
      <div><strong>Price:</strong> {book.price}</div>
      <div><strong>Publisher:</strong> {book.publisher}</div>
      <div><strong>Year:</strong> {book.year}</div>
      <div><strong>ISBN:</strong> {book.isbn}</div>
      <div><strong>Dept:</strong> {book.dept}</div>
      <div><strong>Subject:</strong> {book.subject}</div>
      <div style="grid-column: 1 / -1; margin-top: 10px; line-height: 1.4; color: var(--muted);">
        <strong>Description:</strong><br/>
        {book.description}
      </div>
    </div>
  {/if}
</div>
