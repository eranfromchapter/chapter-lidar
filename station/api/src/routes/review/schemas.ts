// Query schemas of the review lists (contract/openapi/station.yaml operations
// listReviewProjects and listReviewPackages). test/review/openapi-conformance.review.test.ts
// checks them against the document.

/** Default and largest page of a review list. */
export const REVIEW_LIST_DEFAULT_LIMIT = 100;
export const REVIEW_LIST_MAX_LIMIT = 200;

/** GET /review/projects and GET /review/packages query string. Unknown parameters are 400. */
export const reviewListQuerySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    q: { type: "string", minLength: 1, maxLength: 200 },
    limit: {
      type: "integer",
      minimum: 1,
      maximum: REVIEW_LIST_MAX_LIMIT,
      default: REVIEW_LIST_DEFAULT_LIMIT,
    },
  },
} as const;

export interface ReviewListQuery {
  q?: string;
  limit?: number;
}
