/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './lib/src/ui/**/*.dart',
    './lib/src/server.dart',
  ],
  theme: {
    extend: {
      colors: {
        stem: {
          950: '#0f172a',
          900: '#111827',
          800: '#1e293b',
          500: '#38bdf8',
          400: '#7dd3fc',
        },
      },
      fontFamily: {
        sans: ['Manrope', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
