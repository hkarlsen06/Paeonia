// Simulator Debug builds sign in through the development Clerk instance, so a developer can pair the
// simulator with a phone on production Clerk. Unset CLERK_DEV_JWT_ISSUER_DOMAIN before launch.
const devIssuer = process.env.CLERK_DEV_JWT_ISSUER_DOMAIN;

export default {
  providers: [
    {
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN,
      applicationID: "convex",
    },
    ...(devIssuer ? [{ domain: devIssuer, applicationID: "convex" }] : []),
  ],
};
