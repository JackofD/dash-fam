/** @type {import('postcss-load-config').Config} */
const config = {
  plugins: {
    // Tailwind v4 handles vendor prefixing itself, so autoprefixer is gone.
    "@tailwindcss/postcss": {},
  },
};

export default config;
