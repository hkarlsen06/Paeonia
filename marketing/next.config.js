const path = require('path');
const { PHASE_DEVELOPMENT_SERVER } = require('next/constants');

module.exports = (phase) => {
  const isDevelopment = phase === PHASE_DEVELOPMENT_SERVER;

  /** @type {import('next').NextConfig} */
  const nextConfig = {
    ...(isDevelopment
      ? { allowedDevOrigins: ['192.168.10.235'] }
      : { output: 'export' }),
    images: { unoptimized: true },
    trailingSlash: true,
    outputFileTracingRoot: path.join(__dirname, '..'),
    turbopack: {
      root: path.join(__dirname, '..'),
    },
  };

  return nextConfig;
};
