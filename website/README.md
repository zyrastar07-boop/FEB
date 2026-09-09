# FEB Website

Marketing website for the FEB streaming app.

## Pages

- **Home** (`index.html`) - Hero, features, app showcase, download CTA
- **Features** (`features.html`) - Detailed feature breakdowns
- **Download** (`download.html`) - Platform downloads and install guide
- **Contact** (`contact.html`) - Contact form and info
- **Privacy** (`privacy.html`) - Privacy policy
- **Terms** (`terms.html`) - Terms of service
- **DMCA** (`dmca.html`) - DMCA takedown form
- **404** (`404.html`) - 404 error page

## Assets

- `favicon.svg` - App logo as favicon
- `styles.css` - Shared CSS design system
- `main.js` - Shared JavaScript

## SEO

- `sitemap.xml` - XML sitemap for search engines
- `robots.txt` - Crawler instructions
- `humans.txt` - Team and site info

## Setup

Open `index.html` directly in a browser, or serve with any static server:

```bash
# Python
python -m http.server 8000

# Node
npx serve

# PHP
php -S localhost:8000
```

## Analytics

To enable Google Analytics:

1. Create a GA4 property at https://analytics.google.com
2. Copy your Measurement ID (e.g., `G-XXXXXXXXXX`)
3. Uncomment the analytics section in `index.html` and replace `GA_MEASUREMENT_ID`

## Deployment

Static hosting recommended:

- **GitHub Pages**: Push to `gh-pages` branch
- **Netlify**: Drag the `website` folder
- **Vercel**: Import or drag folder
- **Cloudflare Pages**: Connect repo or drag folder

## License

GPL-3.0
