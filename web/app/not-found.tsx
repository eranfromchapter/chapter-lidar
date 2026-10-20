// Not-found page (an unknown address, or a project or package the station does not know), in
// the review screen's type and colours instead of the Next.js default. Shows no data.

export default function NotFound() {
  return (
    <main className="frame">
      <div className="main">
        <div className="page-title">
          <h1>Not found</h1>
          <span className="page-title__meta">
            There is no project, package or page at this address.
          </span>
        </div>
        <span>
          <a href="/">Back to the projects</a>
        </span>
      </div>
    </main>
  );
}
