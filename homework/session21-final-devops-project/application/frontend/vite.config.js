import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In `npm run dev` the /api calls are proxied to a locally running FastAPI (port 8000).
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { '/api': 'http://localhost:8000' } },
});
