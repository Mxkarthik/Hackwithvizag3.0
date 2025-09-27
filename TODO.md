# TODO: Enable Full Translations for Every Page

## Plan Steps
1. **Fix i18n Setup**
   - Update `src/i18n.jsx` to import `tel.json` instead of `es.json` and use "te" key for Telugu.
   - Add i18n import to `src/main.jsx` for initialization.

2. **Add Missing Translation Keys**
   - Update `src/locales/en.json`, `hi.json`, `tel.json` with new sections: "news", "homepage", "sidebar", "header".
   - Add keys for homepage (logo, nav, hero, modal), news (titles, descriptions), sidebar (links), header (search).
   - [x] Updated mentorship section structure in hi.json and tel.json to match en.json (nested form and payment objects).

3. **Update Constants**
   - Modify `src/constants/index.jsx` to use translation keys for navbar links.

4. **Integrate useTranslation in Pages**
   - `src/pages/homepage.jsx`: Add useTranslation and t() for all hardcoded strings.
   - `src/routes/news/page.jsx`: Add useTranslation, t() for title and news items.
   - `src/routes/doubts/doubts.jsx`: Add useTranslation, replace hardcoded with t().
   - `src/routes/Guidence/mentorship.jsx`: Add useTranslation, replace hardcoded with t().
   - `src/layouts/sidebar.jsx`: Add useTranslation for link labels and group titles.
   - `src/layouts/header.jsx`: Add t() for search placeholder.

5. **Test Translations**
   - Run `npm run dev` to start dev server.
   - Use browser to verify language switching on all pages.

## Progress Tracking
- [x] Step 1: Fix i18n setup
- [ ] Step 2: Add translation keys
- [ ] Step 3: Update constants
- [ ] Step 4: Update pages
- [ ] Step 5: Test
