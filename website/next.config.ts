import type { NextConfig } from 'next';

// The complete site is exported as HTML, CSS, JavaScript, and images.
// No application server or hosting-provider account is required at runtime.
const nextConfig: NextConfig = { output: 'export' };
export default nextConfig;
