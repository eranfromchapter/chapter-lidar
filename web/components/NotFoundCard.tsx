// "Not found" (web-review §6.7): an unknown address, project or package. Shows no data.

import { Button } from "./hub/Button";
import { Card } from "./hub/Card";

export function NotFoundCard() {
  return (
    <Card padding="md">
      <div className="hub-stack hub-stack--10">
        <h2 className="page-title">Not found</h2>
        <p className="text-14" style={{ margin: 0 }}>
          There is no project, package or page at this address.
        </p>
        <span>
          <Button variant="outline" size="sm" href="/">
            Back to the projects
          </Button>
        </span>
      </div>
    </Card>
  );
}
