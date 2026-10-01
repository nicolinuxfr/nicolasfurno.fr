import { readFileSync, existsSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pagefind from 'pagefind';

const root = fileURLToPath(new URL('../', import.meta.url));
const publicDir = resolve(root, process.argv[2] || 'public');
const emojis = JSON.parse(readFileSync(join(root, 'data/catemoji.json'), 'utf8'))[0];

function checked(result, operation) {
    if (result.errors?.length) throw new Error(`${operation} : ${result.errors.join('; ')}`);
    return result;
}

async function main() {
    const articles = JSON.parse(readFileSync(join(root, 'data/voiretmanger.json'), 'utf8'));
    if (!existsSync(join(publicDir, 'index.html'))) throw new Error(`Compiler Hugo avant l’indexation : ${publicDir}`);
    try {
        // Mirror pagefind.yml: the Node API does not read the CLI configuration.
        const { index } = checked(await pagefind.createIndex({
            excludeSelectors: ['.meta-photos', '.meta-top .date', '.saison']
        }), 'Création de l’index');
        const site = checked(await index.addDirectory({ path: publicDir }), 'Indexation du blog');
        for (const article of articles) {
            checked(await index.addCustomRecord({
                url: new URL(article.url, "https://voiretmanger.fr").href,
                content: article.title,
                language: 'fr',
                meta: {
                    title: `${emojis[article.category]} ${article.title}`,
                    date: String(Date.parse(article.date) / 1000),
                    category: article.category
                },
                filters: { category: [article.category], source: ["legacy"] },
                sort: { date: String(Date.parse(article.date) / 1000) }
            }), `Indexation de ${article.url}`);
        }
        // Remove stale fragments only once the complete new index is ready.
        rmSync(join(publicDir, 'pagefind'), { recursive: true, force: true });
        checked(await index.writeFiles({ outputPath: join(publicDir, 'pagefind') }), 'Écriture de l’index');
        console.log(`Pagefind : ${site.page_count} pages du blog et ${articles.length} anciennes critiques.`);
    } finally {
        await pagefind.close();
    }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
