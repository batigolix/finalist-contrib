// AI generated
(function () {
  const data = window.issuesData;
  if (!data) {
    document.getElementById('meta').textContent =
      'FOUT: issues.js niet gevonden of leeg. Run update-issues.sh eerst.';
    return;
  }

  // Default sort: newest "changed" first (ISO strings sort correctly).
  const allIssues = data.issues.slice().sort((a, b) => b.changed.localeCompare(a.changed));
  const gen = new Date(data.generated_at);
  document.getElementById('meta').textContent =
    `${data.issues_count} open issues in ${data.projects_count} projecten · gegenereerd ${gen.toLocaleString('nl-NL')}`;

  // ── Populate dropdowns with unique values ───────────────────────
  const projectSelect = document.getElementById('filter-project');
  const statusSelect  = document.getElementById('filter-status');

  // Value = machine_name (URL-safe), label = display title.
  const projectPairs = [...new Map(
    allIssues.map(i => [i.project, i.project_title])
  )].sort((a, b) => a[1].localeCompare(b[1]));
  projectPairs.forEach(([slug, title]) => {
    const opt = document.createElement('option');
    opt.value = slug; opt.textContent = title;
    projectSelect.appendChild(opt);
  });
  [...new Set(allIssues.map(i => i.status_label))].sort().forEach(s => {
    const opt = document.createElement('option');
    opt.value = s; opt.textContent = s;
    statusSelect.appendChild(opt);
  });

  // Preselect from URL hash: #project=<slug>
  const hashParams = new URLSearchParams(location.hash.slice(1));
  const initialProject = hashParams.get('project');
  if (initialProject) projectSelect.value = initialProject;

  // ── Format helpers ─────────────────────────────────────────────
  const statusClass = {
    'Active':                              'status-active',
    'Needs review':                        'status-needsreview',
    'Needs work':                          'status-needswork',
    'Reviewed & tested by the community':  'status-rtbc',
    'Postponed':                           'status-postponed',
    'Postponed (maintainer needs more info)': 'status-postponed',
    'Patch (to be ported)':                'status-postponed',
  };

  function fmtDate(iso) {
    return iso.slice(0, 10);
  }

  // ── Grid ───────────────────────────────────────────────────────
  const grid = new gridjs.Grid({
    columns: [
      {
        id: 'project_title',
        name: 'Project',
        width: '180px',
        formatter: (v, row) => {
          const slug = row.cells[1].data;
          return gridjs.html(
            `<a href="https://www.drupal.org/project/${slug}" target="_blank" rel="noopener">${v}</a>`
          );
        }
      },
      { id: 'project', hidden: true },
      {
        id: 'status_label',
        name: 'Status',
        width: '180px',
        formatter: (v) => gridjs.html(
          `<span class="badge ${statusClass[v] || 'status-closed'}">${v}</span>`
        )
      },
      {
        id: 'title',
        name: 'Titel',
        formatter: (v, row) => {
          const url = row.cells[4].data;
          return gridjs.html(
            `<a href="${url}" target="_blank" rel="noopener">${v}</a>`
          );
        }
      },
      { id: 'url', hidden: true },
      {
        id: 'version',
        name: 'Versie',
        width: '130px',
        formatter: (v) => v
          ? gridjs.html(`<span class="machine">${v}</span>`)
          : gridjs.html('<span class="zero">—</span>')
      },
      {
        id: 'changed',
        name: 'Gewijzigd',
        width: '120px',
        formatter: (v) => gridjs.html(
          `<span title="${v}">${fmtDate(v)}</span>`
        )
      },
    ],
    data: allIssues,
    sort: true,
    search: { placeholder: 'Zoek in titels...' },
    pagination: { limit: 25, summary: true },
    language: {
      search: { placeholder: 'Zoek in titels...' },
      pagination: {
        previous: 'Vorige', next: 'Volgende',
        showing: 'Toont', of: 'van', to: 'tot', results: 'issues'
      },
      noRecordsFound: 'Geen issues gevonden',
    }
  }).render(document.getElementById('table'));

  // ── Filter logic ────────────────────────────────────────────────
  function applyFilters() {
    const p = projectSelect.value;
    const s = statusSelect.value;
    const filtered = allIssues.filter(i =>
      (!p || i.project === p) && (!s || i.status_label === s)
    );
    grid.updateConfig({ data: filtered }).forceRender();
  }

  projectSelect.addEventListener('change', applyFilters);
  statusSelect.addEventListener('change', applyFilters);
  document.getElementById('filter-clear').addEventListener('click', () => {
    projectSelect.value = '';
    statusSelect.value = '';
    applyFilters();
  });

  // Apply initial filter from URL hash.
  if (initialProject) applyFilters();
})();
