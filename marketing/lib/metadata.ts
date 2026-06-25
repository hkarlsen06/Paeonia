export const marketingPreviewImage = {
  url: '/opengraph-image.png',
  width: 1200,
  height: 630,
  alt: 'Paeonia',
};

export const marketingTwitterMetadata = {
  card: 'summary_large_image' as const,
  images: [marketingPreviewImage.url],
};
