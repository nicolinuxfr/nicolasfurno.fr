/* eslint-disable @raycast/prefer-title-case */
import {
  Action,
  ActionPanel,
  Color,
  Detail,
  Form,
  Icon,
  List,
  LocalStorage,
  Toast,
  getPreferenceValues,
  openExtensionPreferences,
  popToRoot,
  showToast,
  useNavigation,
} from "@raycast/api";
import path from "node:path";
import { useEffect, useMemo, useRef, useState } from "react";
import { BackendError, runBackend } from "./backend";
import { formatDisplayValue } from "./format";
import {
  normalizeSeasonSelection,
  prepareSeriesSelection,
  seasonRequestValue,
} from "./series";

type Preferences = { projectRoot: string };
type Category = { id: string; label: string; count: number };
type SearchResult = { id: string; label: string };
type Prepared = {
  category: string;
  id: string;
  label: string;
  suggestedSlug: string;
  seasons: { value: string; label: string }[];
  details: { label: string; value: string }[];
};
type CreationResult = {
  status: "created" | "existing";
  path: string;
  directory: string;
};
type CreationPayload = {
  category: string;
  id: string;
  label: string;
  query?: string;
  title?: string;
  slug: string;
  hours?: string;
  seasons: string;
  files: string[];
  header?: string;
  displayTitle?: string;
};

const searchable = new Set(["film", "serie", "livre", "album", "jeu-video"]);
const categoryIcons: Record<string, Icon> = {
  serie: Icon.Video,
  film: Icon.FilmStrip,
  livre: Icon.Book,
  album: Icon.Music,
  "jeu-video": Icon.GameController,
  photo: Icon.Camera,
};

function errorMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Une erreur inconnue est survenue.";
}

export default function Command() {
  const { projectRoot } = getPreferenceValues<Preferences>();
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const { push } = useNavigation();

  useEffect(() => {
    const controller = new AbortController();
    setError(undefined);
    Promise.all([
      runBackend(projectRoot, "check", {}, controller.signal),
      runBackend<Category[]>(projectRoot, "categories", {}, controller.signal),
      LocalStorage.getItem("lastCategory"),
    ])
      .then(([, loaded, last]) => {
        const ordered = [...loaded].sort((a, b) =>
          a.id === last ? -1 : b.id === last ? 1 : 0,
        );
        setCategories(ordered);
      })
      .catch((reason) => {
        if (!(reason instanceof BackendError && reason.code === "cancelled")) {
          setError(errorMessage(reason));
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [projectRoot]);

  if (error) return <ConfigurationError message={error} />;
  return (
    <List isLoading={loading} searchBarPlaceholder="Filtrer les catégories…">
      {categories.map((category) => (
        <List.Item
          key={category.id}
          icon={categoryIcons[category.id] ?? Icon.Document}
          title={category.label}
          accessories={[{ text: String(category.count) }]}
          actions={
            <ActionPanel>
              <Action
                title="Choisir cette catégorie"
                icon={Icon.ArrowRight}
                onAction={async () => {
                  await LocalStorage.setItem("lastCategory", category.id);
                  push(
                    searchable.has(category.id) ? (
                      <SearchList root={projectRoot} category={category} />
                    ) : (
                      <InitialForm root={projectRoot} category={category} />
                    ),
                  );
                }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

function ConfigurationError({ message }: { message: string }) {
  return (
    <Detail
      markdown={`# Configuration requise\n\n${message}`}
      actions={
        <ActionPanel>
          <Action
            title="Ouvrir les préférences"
            icon={Icon.Gear}
            onAction={openExtensionPreferences}
          />
        </ActionPanel>
      }
    />
  );
}

function SearchList({ root, category }: { root: string; category: Category }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();
  const [retry, setRetry] = useState(0);
  const preparationController = useRef<AbortController | null>(null);
  const { push } = useNavigation();

  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      setResults([]);
      setError(undefined);
      return;
    }
    const controller = new AbortController();
    const timer = setTimeout(() => {
      setLoading(true);
      setError(undefined);
      runBackend<SearchResult[]>(
        root,
        "search",
        { category: category.id, query: trimmed },
        controller.signal,
      )
        .then(setResults)
        .catch((reason) => {
          if (!(reason instanceof BackendError && reason.code === "cancelled"))
            setError(errorMessage(reason));
        })
        .finally(() => {
          if (!controller.signal.aborted) setLoading(false);
        });
    }, 350);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [root, category.id, query, retry]);

  useEffect(() => () => preparationController.current?.abort(), []);

  const openResult = async (result: SearchResult) => {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Préparation…",
    });
    try {
      preparationController.current?.abort();
      preparationController.current = new AbortController();
      const prepared = await runBackend<Prepared>(
        root,
        "prepare",
        {
          category: category.id,
          id: result.id,
          label: result.label,
          query,
        },
        preparationController.current.signal,
      );
      toast.hide();
      push(
        prepared.category === "serie" && prepared.seasons.length > 0 ? (
          <SeasonForm root={root} prepared={prepared} query={query} />
        ) : (
          <CreateForm root={root} prepared={prepared} query={query} />
        ),
      );
    } catch (reason) {
      toast.style = Toast.Style.Failure;
      toast.title = "Préparation impossible";
      toast.message = errorMessage(reason);
    }
  };

  return (
    <List
      isLoading={loading}
      searchText={query}
      onSearchTextChange={setQuery}
      throttle={false}
      filtering={false}
      searchBarPlaceholder={`Rechercher dans ${category.label.toLocaleLowerCase()}…`}
    >
      {error ? (
        <List.Item
          icon={Icon.Warning}
          title="Recherche impossible"
          subtitle={error}
          actions={
            <ActionPanel>
              <Action
                title="Relancer la recherche"
                icon={Icon.ArrowClockwise}
                onAction={() => setRetry((value) => value + 1)}
              />
            </ActionPanel>
          }
        />
      ) : !query ? (
        <List.EmptyView
          icon={Icon.MagnifyingGlass}
          title="Saisissez une recherche"
        />
      ) : results.length === 0 && !loading ? (
        <List.EmptyView title="Aucun résultat" />
      ) : (
        results.map((result) => (
          <List.Item
            key={result.id}
            title={result.label}
            actions={
              <ActionPanel>
                <Action
                  title="Choisir"
                  icon={Icon.ArrowRight}
                  onAction={() => openResult(result)}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}

function SeasonForm({
  root,
  prepared,
  query,
}: {
  root: string;
  prepared: Prepared;
  query?: string;
}) {
  const { push } = useNavigation();
  const [error, setError] = useState<string>();

  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Continuer"
            icon={Icon.ArrowRight}
            onSubmit={(values: { seasons: string[] }) => {
              try {
                const seasons = normalizeSeasonSelection(values.seasons);
                setError(undefined);
                push(
                  <CreateForm
                    root={root}
                    prepared={prepareSeriesSelection(prepared, seasons)}
                    query={query}
                    seasons={seasonRequestValue(seasons)}
                  />,
                );
              } catch (reason) {
                setError(errorMessage(reason));
              }
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Description
        title="Série"
        text={prepared.label.replaceAll("*", "")}
      />
      <Form.TagPicker
        id="seasons"
        title="Saisons"
        defaultValue={["all"]}
        error={error}
        onChange={() => setError(undefined)}
      >
        <Form.TagPicker.Item value="all" title="Toutes les saisons" />
        {prepared.seasons.map((season) => (
          <Form.TagPicker.Item
            key={season.value}
            value={season.value}
            title={season.label}
          />
        ))}
      </Form.TagPicker>
    </Form>
  );
}

function InitialForm({ root, category }: { root: string; category: Category }) {
  const { push } = useNavigation();
  const [files, setFiles] = useState<string[]>([]);
  const [error, setError] = useState<string>();
  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Continuer"
            onSubmit={async (values: { title: string; files?: string[] }) => {
              if (!values.title.trim()) {
                setError("Le titre est obligatoire.");
                return;
              }
              if (category.id === "photo" && files.length === 0) {
                setError("Choisir au moins une photo.");
                return;
              }
              const prepared = await runBackend<Prepared>(root, "prepare", {
                category: category.id,
                title: values.title,
                files,
              });
              push(
                <CreateForm
                  root={root}
                  prepared={prepared}
                  title={values.title}
                  files={files}
                />,
              );
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="title"
        title="Titre"
        placeholder="Titre de l’article"
        error={error}
        onChange={() => setError(undefined)}
      />
      {category.id === "photo" ? (
        <Form.FilePicker
          id="files"
          title="Photos"
          allowMultipleSelection
          canChooseDirectories={false}
          onChange={setFiles}
        />
      ) : null}
    </Form>
  );
}

function CreateForm({
  root,
  prepared,
  query,
  title,
  files = [],
  seasons = "all",
}: {
  root: string;
  prepared: Prepared;
  query?: string;
  title?: string;
  files?: string[];
  seasons?: string;
}) {
  const { push } = useNavigation();
  const [slugError, setSlugError] = useState<string>();
  const photoNames = useMemo(
    () => files.map((file) => ({ path: file, name: path.basename(file) })),
    [files],
  );
  const create = async (values: {
    slug: string;
    hours?: string;
    header?: string;
    displayTitle?: string;
  }) => {
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(values.slug)) {
      setSlugError("Utiliser uniquement minuscules, chiffres et tirets.");
      return;
    }
    if (values.hours && !/^\d+$/.test(values.hours)) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Le temps doit être un entier",
      });
      return;
    }
    const payload: CreationPayload = {
      category: prepared.category,
      id: prepared.id,
      label: prepared.label,
      query,
      title,
      slug: values.slug,
      hours: values.hours,
      seasons,
      files,
      header: values.header,
      displayTitle: values.displayTitle,
    };
    push(<CreationView root={root} payload={payload} />);
  };
  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Créer l’article"
            icon={Icon.Plus}
            onSubmit={create}
          />
        </ActionPanel>
      }
    >
      <Form.Description
        title="Article"
        text={(prepared.label || title || "Nouvel article").replaceAll("*", "")}
      />
      {prepared.details.map((detail) => (
        <Form.Description
          key={detail.label}
          title={detail.label}
          text={formatDisplayValue(detail.value)}
        />
      ))}
      <Form.TextField
        id="slug"
        title="Slug"
        defaultValue={prepared.suggestedSlug}
        error={slugError}
        onChange={() => setSlugError(undefined)}
      />
      {prepared.category === "jeu-video" ? (
        <Form.TextField id="hours" title="Temps de jeu" placeholder="0" />
      ) : null}
      {prepared.category === "livre" ? (
        <Form.TextField
          id="displayTitle"
          title="Titre"
          defaultValue={prepared.label.split(" — ")[0]}
        />
      ) : null}
      {prepared.category === "photo" ? (
        <Form.Dropdown
          id="header"
          title="Image d’en-tête"
          defaultValue={photoNames[0]?.name}
        >
          {photoNames.map((photo) => (
            <Form.Dropdown.Item
              key={photo.path}
              value={photo.name}
              title={photo.name}
            />
          ))}
        </Form.Dropdown>
      ) : null}
    </Form>
  );
}

function CreationView({
  root,
  payload,
}: {
  root: string;
  payload: CreationPayload;
}) {
  const [result, setResult] = useState<CreationResult>();
  const [error, setError] = useState<string>();
  const [attempt, setAttempt] = useState(0);
  const { pop } = useNavigation();

  useEffect(() => {
    const controller = new AbortController();
    setError(undefined);
    const timer = setTimeout(() => {
      runBackend<CreationResult>(root, "create", payload, controller.signal)
        .then(async (created) => {
          setResult(created);
          await showToast({
            style: Toast.Style.Success,
            title:
              created.status === "created"
                ? "Article créé"
                : "Article déjà présent",
          });
        })
        .catch(async (reason) => {
          if (reason instanceof BackendError && reason.code === "cancelled")
            return;
          const message = errorMessage(reason);
          setError(message);
          await showToast({
            style: Toast.Style.Failure,
            title: "Création impossible",
            message,
          });
        });
    }, 0);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [root, payload, attempt]);

  if (result) return <ResultView result={result} />;
  if (error) {
    return (
      <Detail
        markdown={`# Création impossible\n\n${error}`}
        actions={
          <ActionPanel>
            <Action
              title="Réessayer"
              icon={Icon.ArrowClockwise}
              onAction={() => setAttempt((value) => value + 1)}
            />
            <Action
              title="Revenir au formulaire"
              icon={Icon.ArrowLeft}
              onAction={pop}
            />
          </ActionPanel>
        }
      />
    );
  }
  return (
    <Detail
      isLoading
      markdown={`# Création en cours…

Les métadonnées et les images sont en cours de récupération.`}
    />
  );
}

function ResultView({ result }: { result: CreationResult }) {
  const created = result.status === "created";
  return (
    <Detail
      markdown={`# ${created ? "Article créé" : "Article déjà présent"}\n\n\`${result.path}\``}
      metadata={
        <Detail.Metadata>
          <Detail.Metadata.Label
            title="État"
            text={created ? "Créé" : "Existant"}
            icon={{
              source: created ? Icon.CheckCircle : Icon.Info,
              tintColor: created ? Color.Green : Color.Orange,
            }}
          />
        </Detail.Metadata>
      }
      actions={
        <ActionPanel>
          <Action.Open
            title="Ouvrir le dossier"
            target={result.directory}
            icon={Icon.Finder}
          />
          <Action.Open
            title="Ouvrir dans le texte"
            target={result.path}
            icon={Icon.Document}
          />
          <Action.CopyToClipboard
            title="Copier le chemin"
            content={result.path}
          />
          <Action
            title="Créer un autre article"
            icon={Icon.ArrowCounterClockwise}
            onAction={popToRoot}
          />
        </ActionPanel>
      }
    />
  );
}
