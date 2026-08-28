// AI generated
(function () {
  const data = window.projectsData;
  if (!data) {
    document.getElementById('meta').textContent =
      'FOUT: projects.js niet gevonden of leeg. Run update-issues.sh eerst.';
    return;
  }

  const gen = new Date(data.generated_at);
  document.getElementById('meta').textContent =
    `${data.projects_count} projecten · ${data.issues_count} open issues · gegenereerd ${gen.toLocaleString('nl-NL')}`;

  // Default sort: most open issues first.
  const allProjects = data.projects.slice().sort((a, b) => b.open_issues - a.open_issues);

  // Populate filter dropdowns from unique values.
  const kindSelect     = document.getElementById('filter-kind');
  const finalistSelect = document.getElementById('filter-finalist');
  const statSelect     = document.getElementById('filter-maintenance');

  [...new Set(allProjects.map(p => p.kind))].sort().forEach(k => {
    const opt = document.createElement('option');
    opt.value = k; opt.textContent = k;
    kindSelect.appendChild(opt);
  });
  [...new Set(allProjects.flatMap(p => p.finalist_maintainers || []))].sort().forEach(u => {
    const opt = document.createElement('option');
    opt.value = u; opt.textContent = u;
    finalistSelect.appendChild(opt);
  });
  [...new Set(allProjects.map(p => p.maintenance_status).filter(Boolean))].sort().forEach(s => {
    const opt = document.createElement('option');
    opt.value = s; opt.textContent = s;
    statSelect.appendChild(opt);
  });

  // Formatting helpers.
  function kindBadge(k) {
    const cls = ['module', 'theme', 'distribution'].includes(k) ? `kind-${k}` : 'kind-other';
    return `<span class="kind ${cls}">${k}</span>`;
  }
  function statusClass(s) {
    if (!s) return '';
    if (s.includes('Actively'))    return 'status-active';
    if (s.includes('Minimally'))   return 'status-minimal';
    if (s.includes('Seeking'))     return 'status-seeking';
    if (s.includes('Unsupported')) return 'status-unsupported';
    return '';
  }
  function securityLabel(v) {
    if (v === 'covered')     return '<span class="security-covered" title="Covered by security advisory policy">✓ covered</span>';
    if (v === 'not-covered') return '<span class="security-notcovered" title="Not covered by SA policy">not covered</span>';
    return '';
  }

  const grid = new gridjs.Grid({
    columns: [
      {
        id: 'title',
        name: 'Project',
        formatter: (v, row) => gridjs.html(
          `<a href="${row.cells[6].data}" target="_blank" rel="noopener">${v}</a>`
        )
      },
      {
        id: 'kind',
        name: 'Type',
        width: '120px',
        formatter: (v) => gridjs.html(kindBadge(v))
      },
      {
        id: 'latest_version',
        name: 'Versie',
        width: '110px',
        formatter: (v) => v || gridjs.html('<span class="zero">—</span>')
      },
      {
        id: 'supported_cores',
        name: 'Drupal',
        width: '130px',
        // Sort by highest supported major so newest-supporting projects float up.
        sort: { compare: (a, b) => (b?.[b.length - 1] || 0) - (a?.[a.length - 1] || 0) },
        formatter: (v) => {
          if (!v || v.length === 0) return gridjs.html('<span class="zero">—</span>');
          return gridjs.html(v.map(c => `<span class="core core-${c}">${c}</span>`).join(' '));
        }
      },
      {
        id: 'maintenance_status',
        name: 'Maintenance',
        width: '160px',
        formatter: (v) => gridjs.html(`<span class="${statusClass(v)}">${v || ''}</span>`)
      },
      {
        id: 'security_coverage',
        name: 'Security',
        width: '110px',
        formatter: (v) => gridjs.html(securityLabel(v))
      },
      { id: 'url', hidden: true },
      { id: 'machine_name', hidden: true },
      {
        id: 'open_issues',
        name: 'Open issues',
        width: '110px',
        formatter: (v, row) => {
          if (v === 0) return gridjs.html('<span class="zero">0</span>');
          const slug = row.cells[7].data;
          return gridjs.html(`<a href="issues.html#project=${encodeURIComponent(slug)}">${v}</a>`);
        }
      },
      {
        id: 'finalist_maintainers',
        name: 'Finalist maintainers',
        sort: { compare: (a, b) => (a?.length || 0) - (b?.length || 0) },
        formatter: (v) => {
          if (!v || v.length === 0) return '';
          return gridjs.html(v.map(u => `<span class="maintainer">${u}</span>`).join(' '));
        }
      },
    ],
    data: allProjects,
    sort: true,
    search: { placeholder: 'Zoek in project-namen...' },
    pagination: { limit: 25, summary: true },
    language: {
      search: { placeholder: 'Zoek in project-namen...' },
      pagination: {
        previous: 'Vorige', next: 'Volgende',
        showing: 'Toont', of: 'van', to: 'tot', results: 'projecten'
      },
      noRecordsFound: 'Geen projecten gevonden',
    }
  }).render(document.getElementById('table'));

  // Filter logic.
  function applyFilters() {
    const k = kindSelect.value;
    const f = finalistSelect.value;
    const s = statSelect.value;
    const i = document.getElementById('filter-issues').value;
    const filtered = allProjects.filter(p => {
      if (k && p.kind !== k) return false;
      if (f && !(p.finalist_maintainers || []).includes(f)) return false;
      if (s && p.maintenance_status !== s) return false;
      if (i === '>0' && p.open_issues === 0) return false;
      if (i === '=0' && p.open_issues > 0) return false;
      return true;
    });
    grid.updateConfig({ data: filtered }).forceRender();
  }

  [kindSelect, finalistSelect, statSelect, document.getElementById('filter-issues')]
    .forEach(el => el.addEventListener('change', applyFilters));
  document.getElementById('filter-clear').addEventListener('click', () => {
    [kindSelect, finalistSelect, statSelect, document.getElementById('filter-issues')]
      .forEach(el => el.value = '');
    applyFilters();
  });
})();
