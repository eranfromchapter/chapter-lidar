import type { ProjectNavData } from "@/lib/projects";

export interface ProjectNavProps {
  readonly data: ProjectNavData;
  readonly selectedDealId?: string | undefined;
}

/** "Find a project" column: search and the project list with each latest status. */
export function ProjectNav({ data, selectedDealId }: ProjectNavProps) {
  return (
    <nav aria-label="Projects" className="project-nav">
      <form action="/" method="get" role="search" className="project-search">
        <label htmlFor="search" className="caption">
          Find a project
        </label>
        <input
          id="search"
          name="q"
          type="search"
          className="search-input"
          placeholder="Address or deal"
          defaultValue={data.query}
          maxLength={200}
          autoComplete="off"
        />
      </form>
      {data.ok ? (
        <ul className="project-list">
          {data.items.length === 0 ? (
            <li className="project-list__empty">
              {data.query.length > 0 ? "No project matches this search." : "No projects yet."}
            </li>
          ) : (
            data.items.map((item) => (
              <li key={item.dealId} className="project-list__item">
                <a
                  className="project-list__link"
                  href={`/projects/${encodeURIComponent(item.dealId)}`}
                  aria-current={item.dealId === selectedDealId ? "page" : undefined}
                >
                  <span className="project-list__name">{item.address}</span>
                  <span className={`project-list__status tone-${item.tone}`}>
                    {item.statusText}
                  </span>
                </a>
              </li>
            ))
          )}
        </ul>
      ) : (
        <p role="alert" className="notice">
          {data.message}
        </p>
      )}
    </nav>
  );
}
