import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: true, allowedHosts: true, strictPort: false },
  build: { outDir: 'dist', emptyOutDir: true },
});
