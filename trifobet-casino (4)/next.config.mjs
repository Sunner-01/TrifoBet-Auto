/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  experimental: { cpus: 1 },
  images: {
    unoptimized: true,
  },
}

export default nextConfig

