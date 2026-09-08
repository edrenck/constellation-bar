import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'ConstellationBar — Your desktop, connected.', description: 'A native macOS workspace and status bar. Explore three layouts, five appearances, and interactive widgets. Public alpha in preparation.' };
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) {return <html lang="en"><body>{children}</body></html>;}
