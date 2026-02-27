// import { useState } from "react";
// import reactLogo from "./assets/react.svg";
// import { invoke } from "@tauri-apps/api/core";
// import "./App.css";

// function App() {
//   const [greetMsg, setGreetMsg] = useState("");
//   const [name, setName] = useState("");

//   async function greet() {
//     // Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
//     setGreetMsg(await invoke("greet", { name }));
//   }

//   return (
//     <main className="container">
//       <h1>Welcome to Tauri + React</h1>

//       <div className="row">
//         <a href="https://vite.dev" target="_blank">
//           <img src="/vite.svg" className="logo vite" alt="Vite logo" />
//         </a>
//         <a href="https://tauri.app" target="_blank">
//           <img src="/tauri.svg" className="logo tauri" alt="Tauri logo" />
//         </a>
//         <a href="https://react.dev" target="_blank">
//           <img src={reactLogo} className="logo react" alt="React logo" />
//         </a>
//       </div>
//       <p>Click on the Tauri, Vite, and React logos to learn more.</p>

//       <form
//         className="row"
//         onSubmit={(e) => {
//           e.preventDefault();
//           greet();
//         }}
//       >
//         <input
//           id="greet-input"
//           onChange={(e) => setName(e.currentTarget.value)}
//           placeholder="Enter a name..."
//         />
//         <button type="submit">Greet</button>
//       </form>
//       <p>{greetMsg}</p>
//     </main>
//   );
// }

// export default App;


import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";

// ── Types ──────────────────────────────────────────────────────────────────
interface Document {
  id: string;
  filename: string;
  content_type: string;
  file_size: number;
  text_content: string;
  status: string;
  is_synced: boolean;
  needs_upload: boolean;
  tags: string[];
  created_at: string;
  object_key: string;
  local_path: string;
}

interface SyncStatus {
  is_syncing: boolean;
  last_sync_at: string | null;
  pending_count: number;
  failed_count: number;
  connection_online: boolean;
}

interface AuthResult {
  authenticated: boolean;
  server_url: string | null;
  username: string | null;
}

interface DIDResult {
  did: string;
  public_key_multibase: string;
}

interface PendingOp {
  id: string;
  op_type: string;
  doc_id: string;
  status: string;
  retry_count: number;
  error_msg: string | null;
}

interface Toast {
  id: number;
  msg: string;
  type: "info" | "success" | "error";
}

// ── Styles ─────────────────────────────────────────────────────────────────
const css = `
  @import url('https://fonts.googleapis.com/css2?family=Space+Mono:ital,wght@0,400;0,700;1,400&family=Syne:wght@400;600;700;800&display=swap');

  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:       #0a0a0a;
    --surface:  #111111;
    --border:   #222222;
    --accent:   #e8ff3c;
    --accent2:  #ff4d6d;
    --text:     #f0f0f0;
    --muted:    #555555;
    --success:  #3cffa0;
    --warning:  #ffb03c;
    --mono:     'Space Mono', monospace;
    --sans:     'Syne', sans-serif;
  }

  html, body, #root { height: 100%; background: var(--bg); color: var(--text); font-family: var(--mono); font-size: 13px; line-height: 1.6; overflow: hidden; }
  ::-webkit-scrollbar { width: 4px; } ::-webkit-scrollbar-track { background: var(--bg); } ::-webkit-scrollbar-thumb { background: var(--border); }

  .app { display: grid; grid-template-columns: 220px 1fr; grid-template-rows: 48px 1fr; height: 100vh; overflow: hidden; }

  .header { grid-column: 1 / -1; display: flex; align-items: center; justify-content: space-between; padding: 0 20px; border-bottom: 1px solid var(--border); background: var(--surface); z-index: 10; }
  .logo { font-family: var(--sans); font-weight: 800; font-size: 18px; letter-spacing: -0.5px; color: var(--accent); }
  .logo span { color: var(--text); }
  .header-right { display: flex; align-items: center; gap: 16px; }
  .sync-badge { display: flex; align-items: center; gap: 6px; font-size: 11px; color: var(--muted); padding: 4px 10px; border: 1px solid var(--border); }
  .sync-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--muted); }
  .sync-dot.online  { background: var(--success); box-shadow: 0 0 6px var(--success); }
  .sync-dot.syncing { background: var(--accent); animation: pulse 1s infinite; }
  .sync-dot.failed  { background: var(--accent2); }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

  .sidebar { border-right: 1px solid var(--border); background: var(--surface); display: flex; flex-direction: column; overflow-y: auto; }
  .nav-section { padding: 12px 0; border-bottom: 1px solid var(--border); }
  .nav-label { font-size: 10px; letter-spacing: 2px; color: var(--muted); padding: 0 16px 6px; text-transform: uppercase; }
  .nav-item { display: flex; align-items: center; gap: 10px; padding: 7px 16px; cursor: pointer; font-size: 12px; color: var(--muted); transition: all 0.1s; border-left: 2px solid transparent; }
  .nav-item:hover { color: var(--text); background: rgba(255,255,255,0.03); }
  .nav-item.active { color: var(--accent); border-left-color: var(--accent); background: rgba(232,255,60,0.04); }
  .nav-icon { font-size: 14px; width: 18px; text-align: center; }
  .nav-badge { margin-left: auto; background: var(--accent2); color: #000; font-size: 9px; padding: 1px 5px; font-weight: 700; }

  .main { overflow-y: auto; background: var(--bg); }
  .panel { padding: 24px; max-width: 860px; }
  .panel-title { font-family: var(--sans); font-size: 22px; font-weight: 800; letter-spacing: -0.5px; margin-bottom: 4px; }
  .panel-sub { color: var(--muted); font-size: 11px; margin-bottom: 24px; }

  .card { background: var(--surface); border: 1px solid var(--border); padding: 16px; margin-bottom: 12px; }
  .card-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
  .card-title { font-family: var(--sans); font-size: 13px; font-weight: 700; letter-spacing: 0.5px; text-transform: uppercase; }

  .btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px; font-family: var(--mono); font-size: 11px; font-weight: 700; cursor: pointer; border: 1px solid var(--border); background: transparent; color: var(--text); letter-spacing: 0.5px; transition: all 0.1s; }
  .btn:hover { border-color: var(--text); }
  .btn:active { transform: translateY(1px); }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .btn-accent { background: var(--accent); color: #000; border-color: var(--accent); }
  .btn-accent:hover { background: #fff; border-color: #fff; }
  .btn-danger { border-color: var(--accent2); color: var(--accent2); }
  .btn-danger:hover { background: var(--accent2); color: #000; }
  .btn-sm { padding: 4px 10px; font-size: 10px; }
  .btn-row { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px; }

  .input { width: 100%; background: var(--bg); border: 1px solid var(--border); color: var(--text); font-family: var(--mono); font-size: 12px; padding: 8px 12px; outline: none; transition: border-color 0.1s; }
  .input:focus { border-color: var(--accent); }
  .input::placeholder { color: var(--muted); }
  .input-group { display: flex; flex-direction: column; gap: 6px; margin-bottom: 12px; }
  .input-label { font-size: 10px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--muted); }
  .input-row { display: flex; gap: 8px; }
  .input-row .input { flex: 1; }

  .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 20px; }
  .stat { background: var(--surface); border: 1px solid var(--border); padding: 16px; }
  .stat-value { font-family: var(--sans); font-size: 28px; font-weight: 800; line-height: 1; margin-bottom: 4px; }
  .stat-label { font-size: 10px; letter-spacing: 1.5px; color: var(--muted); text-transform: uppercase; }

  .doc-list { display: flex; flex-direction: column; gap: 6px; }
  .doc-item { background: var(--surface); border: 1px solid var(--border); padding: 12px 16px; display: flex; align-items: center; gap: 12px; transition: border-color 0.1s; }
  .doc-item:hover { border-color: #333; }
  .doc-icon { font-size: 20px; width: 32px; text-align: center; flex-shrink: 0; }
  .doc-info { flex: 1; min-width: 0; }
  .doc-name { font-family: var(--sans); font-size: 13px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .doc-meta { font-size: 10px; color: var(--muted); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .doc-status { flex-shrink: 0; display: flex; align-items: center; gap: 6px; }

  .tag { font-size: 9px; padding: 2px 6px; letter-spacing: 1px; text-transform: uppercase; font-weight: 700; }
  .tag-synced  { background: rgba(60,255,160,0.1); color: var(--success); border: 1px solid rgba(60,255,160,0.2); }
  .tag-local   { background: rgba(255,176,60,0.1); color: var(--warning); border: 1px solid rgba(255,176,60,0.2); }
  .tag-failed  { background: rgba(255,77,109,0.1); color: var(--accent2); border: 1px solid rgba(255,77,109,0.2); }

  .did-box { background: var(--bg); border: 1px solid var(--border); padding: 12px; font-size: 11px; word-break: break-all; color: var(--accent); margin: 8px 0; line-height: 1.8; }

  .status-row { display: flex; align-items: center; justify-content: space-between; padding: 7px 12px; background: var(--bg); border: 1px solid var(--border); font-size: 11px; margin-bottom: 4px; }
  .status-key { color: var(--muted); flex-shrink: 0; margin-right: 12px; }
  .status-val { color: var(--text); font-family: var(--mono); text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .status-val.green  { color: var(--success); }
  .status-val.yellow { color: var(--warning); }
  .status-val.red    { color: var(--accent2); }

  .toast-container { position: fixed; bottom: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px; z-index: 999; }
  .toast { padding: 10px 16px; font-size: 11px; border-left: 3px solid var(--accent); background: var(--surface); border-top: 1px solid var(--border); border-right: 1px solid var(--border); border-bottom: 1px solid var(--border); animation: slideIn 0.2s ease; max-width: 320px; word-break: break-word; }
  .toast.error   { border-left-color: var(--accent2); }
  .toast.success { border-left-color: var(--success); }
  @keyframes slideIn { from { transform: translateX(20px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }

  .empty { padding: 48px; text-align: center; color: var(--muted); border: 1px dashed var(--border); }
  .empty-icon { font-size: 32px; margin-bottom: 12px; }
  .empty-text { font-size: 12px; line-height: 1.8; }

  .divider { height: 1px; background: var(--border); margin: 16px 0; }

  .op-item { background: var(--bg); border: 1px solid var(--border); padding: 10px 12px; margin-bottom: 6px; }
  .op-type  { font-size: 11px; font-weight: 700; color: var(--accent); margin-bottom: 4px; }
  .op-error { font-size: 10px; color: var(--accent2); word-break: break-all; line-height: 1.6; }
  .op-meta  { font-size: 10px; color: var(--muted); margin-top: 4px; }

  .file-picker { display: flex; gap: 8px; align-items: center; }
  .file-path { flex: 1; background: var(--bg); border: 1px solid var(--border); padding: 8px 12px; font-size: 11px; color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .reg-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
`;

// ── Helpers ────────────────────────────────────────────────────────────────
let toastId = 0;

function fileIcon(ct: string) {
  if (ct?.includes("image")) return "🖼️";
  if (ct?.includes("pdf"))   return "📄";
  if (ct?.includes("video")) return "🎬";
  if (ct?.includes("audio")) return "🎵";
  return "📝";
}

function shortHash(s: string) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = Math.imul(31, h) + s.charCodeAt(i) | 0;
  return Math.abs(h).toString(16).slice(0, 12);
}

function guessContentType(filename: string): string {
  const ext = filename.split(".").pop()?.toLowerCase();
  const map: Record<string, string> = {
    txt: "text/plain", pdf: "application/pdf",
    jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif",
    mp4: "video/mp4", mov: "video/quicktime",
    doc: "application/msword", docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  };
  return map[ext ?? ""] ?? "application/octet-stream";
}

// ── App ────────────────────────────────────────────────────────────────────
export default function App() {
  const [tab, setTab]               = useState("dashboard");
  const [docs, setDocs]             = useState<Document[]>([]);
  const [syncStatus, setSyncStatus] = useState<SyncStatus | null>(null);
  const [auth, setAuth]             = useState<AuthResult | null>(null);
  const [did, setDid]               = useState<DIDResult | null>(null);
  const [pendingOps, setPendingOps] = useState<PendingOp[]>([]);
  const [toasts, setToasts]         = useState<Toast[]>([]);
  const [loading, setLoading]       = useState(false);
  const [search, setSearch]         = useState("");

  // Registration
  const [regUsername, setRegUsername]   = useState("");
  const [regPassword, setRegPassword]   = useState("");
  const [regServerUrl, setRegServerUrl] = useState("http://localhost:4000");
  const [regToken, setRegToken]         = useState("");
  const [regDone, setRegDone]           = useState(false);

  // Manual auth
  const [manualToken, setManualToken]   = useState("");
  const [manualServer, setManualServer] = useState("http://localhost:4000");
  const [manualUser, setManualUser]     = useState("");

  // New doc
  const [docFilename, setDocFilename] = useState("");
  const [docContent, setDocContent]   = useState("");
  const [docTags, setDocTags]         = useState("");
  const [docFilePath, setDocFilePath] = useState("");

  // ── Toast ──────────────────────────────────────────────────────────────
  const toast = useCallback((msg: string, type: Toast["type"] = "info") => {
    const id = toastId++;
    setToasts(t => [...t, { id, msg, type }]);
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 4000);
  }, []);

  // ── Data loading ───────────────────────────────────────────────────────
  const load = useCallback(async () => {
    try {
      const [d, s, a] = await Promise.all([
        invoke<Document[]>("get_documents"),
        invoke<SyncStatus>("get_sync_status"),
        invoke<AuthResult>("is_authenticated"),
      ]);
      setDocs(d);
      setSyncStatus(s);
      setAuth(a);
    } catch (e) { console.error(e); }
  }, []);

  const loadOps = useCallback(async () => {
    try {
      const r = await invoke<{ operations: PendingOp[] }>("get_pending_operations");
      setPendingOps(r?.operations ?? []);
    } catch (e) { console.error(e); }
  }, []);

  useEffect(() => {
    load();
    const i = setInterval(load, 5000);
    return () => clearInterval(i);
  }, [load]);

  useEffect(() => {
    if (tab === "sync") loadOps();
  }, [tab, loadOps]);



  const handleLogout = async () => {
    try {
      await invoke("clear_oauth_token");
      setRegDone(false); setRegToken("");
      await load();
      toast("Signed out");
    } catch (e) { toast(String(e), "error"); }
  };



  const handleManualLogin = async () => {
    if (!manualToken.trim()) { toast("Paste your token", "error"); return; }
    setLoading(true);
    try {
      await invoke("store_oauth_token", { token: manualToken, serverUrl: manualServer, username: manualUser });
      await load();
      toast("Authenticated successfully", "success");
    } catch (e) { toast(String(e), "error"); }
    finally { setLoading(false); }
  };

  // ── Registration ────────────────────────────────────────────────────────
  const handleRegister = async () => {
    if (!regUsername.trim() || !regPassword.trim()) {
      toast("Enter username and password", "error"); return;
    }
    setLoading(true);
    try {
      // Step 1 — Register OAuth app
      const appRes = await fetch("http://localhost:4001/api/v1/apps", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_name: "ALEM Desktop",
          redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
          scopes: "read write"
        })
      });
      const app = await appRes.json();
  
      // Step 2 — Get OAuth token
      const tokenRes = await fetch("http://localhost:4001/oauth/token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          grant_type: "password",
          username: regUsername,
          password: regPassword,
          client_id: app.client_id,
          client_secret: app.client_secret,
          scope: "read write"
        })
      });
      const tokenData = await tokenRes.json();
      const token = tokenData.access_token;
      if (!token) { toast("Failed to get token", "error"); return; }
      setRegToken(token);
  
      // Step 3 — Store token in OS Keychain
      await invoke("store_oauth_token", {
        token,
        serverUrl: regServerUrl,
        username: regUsername
      });
  
      // Step 4 — Create namespace → server auto-generates DID
      const nsRes = await fetch(`${regServerUrl}/api/v1/namespaces`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`
        },
        body: JSON.stringify({})
      });
      const nsData = await nsRes.json();
  
      // Step 5 — Store server-generated DID locally
      if (nsData.did) {
        await invoke("store_server_did", { did: nsData.did });
        setDid({ did: nsData.did, public_key_multibase: nsData.did.replace("did:key:", "") });
        toast(`DID received from server: ${nsData.did.slice(0, 30)}...`, "info");
      }
  
      setRegDone(true);
      await load();
      toast(`Welcome ${regUsername}! Account + DID ready.`, "success");
  
    } catch (e) {
      toast(String(e), "error");
    } finally {
      setLoading(false);
    }
  };
  // ── DID ─────────────────────────────────────────────────────────────────
  const handleGenerateDID = async () => {
    setLoading(true);
    try {
      const result = await invoke<DIDResult>("generate_did");
      setDid(result);
      toast("DID generated — use Link to Namespace to attach it", "success");
    } catch (e) { toast(String(e), "error"); }
    finally { setLoading(false); }
  };

  const handleGetDID = async () => {
    try {
      const result = await invoke<DIDResult | null>("get_stored_did");
      if (result) { setDid(result); toast("DID loaded"); }
      else toast("No DID found — generate one first", "error");
    } catch (e) { toast(String(e), "error"); }
  };

  const handleLinkDID = async () => {
    if (!did) { toast("Generate a DID first", "error"); return; }
    const token = regToken || manualToken;
    const server = regServerUrl || manualServer;
    if (!token) { toast("Login first", "error"); return; }
    try {
      const res = await fetch(`${server}/api/v1/namespaces`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
        body: JSON.stringify({ did: did.did, identity_type: "did" })
      });
      if (res.ok) toast("DID linked to namespace — identity_type: hybrid", "success");
      else { const d = await res.json(); toast(`Failed: ${d.error ?? res.status}`, "error"); }
    } catch (e) { toast(String(e), "error"); }
  };

  // ── File picker ─────────────────────────────────────────────────────────
  const handlePickFile = async () => {
    try {
      const selected = await open({ multiple: false, title: "Select file" });
      if (selected && typeof selected === "string") {
        setDocFilePath(selected);
        const fname = selected.replace(/\\/g, "/").split("/").pop() ?? "";
        if (!docFilename) setDocFilename(fname);
      }
    } catch {
      toast("File picker not available — enter path manually", "info");
    }
  };

  // ── Create document ──────────────────────────────────────────────────────
  const handleCreateDoc = async () => {
    if (!docFilename.trim()) { toast("Enter a filename", "error"); return; }
    setLoading(true);
    try {
      await invoke("create_document", {
        input: {
          filename: docFilename,
          content_type: guessContentType(docFilename),
          local_path: docFilePath || "C:/test.txt",
          file_size: docContent.length || 100,
          content_hash: shortHash(docFilename + Date.now()),
          text_content: docContent || docFilename,
          metadata: {},
          tags: docTags ? docTags.split(",").map(t => t.trim()).filter(Boolean) : [],
        }
      });
      setDocFilename(""); setDocContent(""); setDocTags(""); setDocFilePath("");
      await load();
      toast("Document saved locally — will sync automatically", "success");
    } catch (e) { toast(String(e), "error"); }
    finally { setLoading(false); }
  };

  // ── Sync ─────────────────────────────────────────────────────────────────
  const handleSync = async () => {
    try {
      await invoke("trigger_sync");
      toast("Sync triggered");
      setTimeout(() => { load(); loadOps(); }, 6000);
    } catch (e) { toast(String(e), "error"); }
  };

  const handleRetry = async () => {
    try {
      const n = await invoke<number>("retry_failed_operations");
      toast(`Retrying ${n} operations`);
      setTimeout(() => { load(); loadOps(); }, 6000);
    } catch (e) { toast(String(e), "error"); }
  };

  const handleSearch = async () => {
    if (!search.trim()) { await load(); return; }
    try {
      const r = await invoke<Document[]>("search_documents", { query: search });
      setDocs(r);
    } catch (e) { toast(String(e), "error"); }
  };

  const handleDeleteDoc = async (id: string) => {
    try {
      await invoke("delete_document", { id });
      await load();
      toast("Document deleted");
    } catch (e) { toast(String(e), "error"); }
  };

  // ── Derived ───────────────────────────────────────────────────────────────
  const syncedDocs  = docs.filter(d => d.is_synced);
  const pendingDocs = docs.filter(d => !d.is_synced);
  const failedOps   = pendingOps.filter(o => o.status === "failed");
  const queuedOps   = pendingOps.filter(o => o.status === "pending");

  const dotClass = () => {
    if (!syncStatus) return "";
    if (syncStatus.is_syncing) return "syncing";
    if (syncStatus.failed_count > 0) return "failed";
    if (syncStatus.connection_online) return "online";
    return "";
  };

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <>
      <style>{css}</style>
      <div className="app">

        {/* ── Header ── */}
        <header className="header">
          <div className="logo">ALEM<span>.</span></div>
          <div className="header-right">
            {syncStatus && (
              <div className="sync-badge">
                <div className={`sync-dot ${dotClass()}`} />
                {syncStatus.is_syncing ? "SYNCING"
                  : syncStatus.connection_online ? "ONLINE" : "OFFLINE"}
                {syncStatus.pending_count > 0 && ` · ${syncStatus.pending_count} pending`}
                {syncStatus.failed_count > 0  && ` · ${syncStatus.failed_count} failed`}
              </div>
            )}
            {auth?.authenticated && (
              <span style={{ fontSize: 11, color: "var(--muted)" }}>◉ {auth.username}</span>
            )}
          </div>
        </header>

        {/* ── Sidebar ── */}
        <nav className="sidebar">
          <div className="nav-section">
            <div className="nav-label">Main</div>
            {[
              { id: "dashboard", icon: "◈", label: "Dashboard" },
              { id: "documents", icon: "◉", label: "Documents", badge: pendingDocs.length || null },
              { id: "create",    icon: "⊕", label: "New Document" },
              { id: "search",    icon: "⊘", label: "Search" },
            ].map(n => (
              <div key={n.id} className={`nav-item ${tab === n.id ? "active" : ""}`} onClick={() => setTab(n.id)}>
                <span className="nav-icon">{n.icon}</span>{n.label}
                {n.badge ? <span className="nav-badge">{n.badge}</span> : null}
              </div>
            ))}
          </div>

          <div className="nav-section">
            <div className="nav-label">Identity</div>
            {[
              { id: "register", icon: "⊞", label: "Register" },
              { id: "auth",     icon: "◎", label: "Sign In" },
              { id: "did",      icon: "◆", label: "DID" },
            ].map(n => (
              <div key={n.id} className={`nav-item ${tab === n.id ? "active" : ""}`} onClick={() => setTab(n.id)}>
                <span className="nav-icon">{n.icon}</span>{n.label}
              </div>
            ))}
          </div>

          <div className="nav-section">
            <div className="nav-label">System</div>
            {[
              { id: "sync",   icon: "↻", label: "Sync", badge: (syncStatus?.failed_count ?? 0) > 0 ? syncStatus!.failed_count : null },
              { id: "health", icon: "◇", label: "Health" },
            ].map(n => (
              <div key={n.id} className={`nav-item ${tab === n.id ? "active" : ""}`} onClick={() => { setTab(n.id); if (n.id === "sync") loadOps(); }}>
                <span className="nav-icon">{n.icon}</span>{n.label}
                {n.badge ? <span className="nav-badge">{n.badge}</span> : null}
              </div>
            ))}
          </div>
        </nav>

        {/* ── Main ── */}
        <main className="main">

          {/* Dashboard */}
          {tab === "dashboard" && (
            <div className="panel">
              <div className="panel-title">Dashboard</div>
              <div className="panel-sub">Local-first · offline-capable · synced to Linode sqld + S3</div>

              <div className="stats">
                {[
                  { v: docs.length,         label: "Total Docs",  color: "var(--accent)" },
                  { v: syncedDocs.length,   label: "Synced",      color: "var(--success)" },
                  { v: pendingDocs.length,  label: "Pending",     color: "var(--warning)" },
                  { v: syncStatus?.failed_count ?? 0, label: "Failed", color: (syncStatus?.failed_count ?? 0) > 0 ? "var(--accent2)" : "var(--muted)" },
                ].map(s => (
                  <div key={s.label} className="stat">
                    <div className="stat-value" style={{ color: s.color }}>{s.v}</div>
                    <div className="stat-label">{s.label}</div>
                  </div>
                ))}
              </div>

              <div className="card">
                <div className="card-header">
                  <div className="card-title">System Status</div>
                  <button className="btn btn-sm" onClick={load}>↻</button>
                </div>
                {[
                  { k: "Auth",      v: auth?.authenticated ? `✓ ${auth.username}` : "Not authenticated", c: auth?.authenticated ? "green" : "red" },
                  { k: "Server",    v: auth?.server_url ?? "—", c: "" },
                  { k: "Online",    v: syncStatus?.connection_online ? "Yes" : "No", c: syncStatus?.connection_online ? "green" : "yellow" },
                  { k: "Last Sync", v: syncStatus?.last_sync_at ?? "Never", c: "" },
                  { k: "Pending",   v: String(syncStatus?.pending_count ?? 0), c: (syncStatus?.pending_count ?? 0) > 0 ? "yellow" : "green" },
                  { k: "Failed",    v: String(syncStatus?.failed_count ?? 0),  c: (syncStatus?.failed_count ?? 0) > 0 ? "red" : "green" },
                  { k: "DID",       v: did ? did.did.slice(0, 30) + "…" : "Not generated", c: did ? "green" : "" },
                ].map(row => (
                  <div key={row.k} className="status-row">
                    <span className="status-key">{row.k}</span>
                    <span className={`status-val ${row.c}`}>{row.v}</span>
                  </div>
                ))}
              </div>

              <div className="btn-row">
                <button className="btn btn-accent" onClick={handleSync}>↑ Sync Now</button>
                {(syncStatus?.failed_count ?? 0) > 0 && (
                  <button className="btn btn-danger" onClick={handleRetry}>↻ Retry Failed ({syncStatus?.failed_count})</button>
                )}
                <button className="btn" onClick={() => setTab("create")}>⊕ New Document</button>
              </div>
            </div>
          )}

          {/* Documents */}
          {tab === "documents" && (
            <div className="panel">
              <div className="panel-title">Documents</div>
              <div className="panel-sub">{docs.length} total · {syncedDocs.length} synced to Linode · {pendingDocs.length} local only</div>

              {docs.length === 0 ? (
                <div className="empty">
                  <div className="empty-icon">◉</div>
                  <div className="empty-text">No documents yet.<br />Go to New Document to create one.</div>
                </div>
              ) : (
                <div className="doc-list">
                  {docs.map(doc => (
                    <div key={doc.id} className="doc-item">
                      <div className="doc-icon">{fileIcon(doc.content_type)}</div>
                      <div className="doc-info">
                        <div className="doc-name">{doc.filename}</div>
                        <div className="doc-meta">
                          {doc.content_type} · {doc.created_at?.slice(0, 10)}
                          {doc.object_key ? ` · S3 ✓` : ""}
                        </div>
                      </div>
                      <div className="doc-status">
                        <span className={`tag ${doc.is_synced ? "tag-synced" : doc.status === "failed" ? "tag-failed" : "tag-local"}`}>
                          {doc.is_synced ? "synced" : doc.status ?? "local"}
                        </span>
                        <button className="btn btn-sm btn-danger" onClick={() => handleDeleteDoc(doc.id)}>✕</button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* New Document */}
          {tab === "create" && (
            <div className="panel">
              <div className="panel-title">New Document</div>
              <div className="panel-sub">Saved locally first — syncs to Linode S3 when online</div>

              <div className="card">
                <div className="input-group">
                  <div className="input-label">File (pick or enter path manually)</div>
                  <div className="file-picker">
                    <div className="file-path">{docFilePath || "No file selected"}</div>
                    <button className="btn" onClick={handlePickFile}>Browse</button>
                  </div>
                </div>

                <div className="input-group">
                  <div className="input-label">Filename</div>
                  <input className="input" placeholder="document.txt" value={docFilename} onChange={e => setDocFilename(e.target.value)} />
                </div>

                <div className="input-group">
                  <div className="input-label">Content / Description (for search)</div>
                  <textarea className="input" placeholder="Document text content..." value={docContent} onChange={e => setDocContent(e.target.value)} rows={4} style={{ resize: "vertical" }} />
                </div>

                <div className="input-group">
                  <div className="input-label">Tags (comma separated)</div>
                  <input className="input" placeholder="work, invoice, 2026" value={docTags} onChange={e => setDocTags(e.target.value)} />
                </div>

                <div className="btn-row">
                  <button className="btn btn-accent" onClick={handleCreateDoc} disabled={loading}>
                    {loading ? "Saving..." : "⊕ Create Document"}
                  </button>
                  <button className="btn" onClick={handleSync}>↑ Sync Now</button>
                </div>
              </div>
            </div>
          )}

          {/* Search */}
          {tab === "search" && (
            <div className="panel">
              <div className="panel-title">Search</div>
              <div className="panel-sub">SQLite FTS5 full-text search — works completely offline</div>

              <div className="input-row" style={{ marginBottom: 16 }}>
                <input className="input" placeholder="Search documents..." value={search} onChange={e => setSearch(e.target.value)} onKeyDown={e => e.key === "Enter" && handleSearch()} />
                <button className="btn btn-accent" onClick={handleSearch}>Search</button>
                <button className="btn" onClick={() => { setSearch(""); load(); }}>Clear</button>
              </div>

              <div className="doc-list">
                {docs.map(doc => (
                  <div key={doc.id} className="doc-item">
                    <div className="doc-icon">{fileIcon(doc.content_type)}</div>
                    <div className="doc-info">
                      <div className="doc-name">{doc.filename}</div>
                      <div className="doc-meta">{doc.text_content?.slice(0, 100)}</div>
                    </div>
                    <span className={`tag ${doc.is_synced ? "tag-synced" : "tag-local"}`}>
                      {doc.is_synced ? "synced" : "local"}
                    </span>
                  </div>
                ))}
                {docs.length === 0 && search && (
                  <div className="empty">
                    <div className="empty-icon">⊘</div>
                    <div className="empty-text">No results for "{search}"</div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Register */}
          {tab === "register" && (
            <div className="panel">
              <div className="panel-title">Register</div>
              <div className="panel-sub">Creates Pleroma OAuth token → stores in OS Keychain → creates namespace in PostgreSQL</div>

              {auth?.authenticated ? (
                <div className="card">
                  <div className="card-header">
                    <div className="card-title">Already Signed In</div>
                    <span className="tag tag-synced">Active</span>
                  </div>
                  <div className="status-row"><span className="status-key">Username</span><span className="status-val green">{auth.username}</span></div>
                  <div className="status-row"><span className="status-key">Server</span><span className="status-val">{auth.server_url}</span></div>
                  <div className="btn-row">
                    <button className="btn" onClick={() => setTab("did")}>◆ Generate DID →</button>
                    <button className="btn btn-danger" onClick={handleLogout}>Sign Out</button>
                  </div>
                </div>
              ) : regDone ? (
                <div className="card">
                  <div className="card-header">
                    <div className="card-title">Registration Complete ✓</div>
                    <span className="tag tag-synced">Done</span>
                  </div>
                  <div className="status-row"><span className="status-key">Username</span><span className="status-val green">{regUsername}</span></div>
                  <div className="status-row"><span className="status-key">Server</span><span className="status-val">{regServerUrl}</span></div>
                  <div className="status-row"><span className="status-key">Token</span><span className="status-val">Stored in OS Keychain ✓</span></div>
                  <div className="status-row"><span className="status-key">Namespace</span><span className="status-val green">Created in PostgreSQL ✓</span></div>
                  <div style={{ marginTop: 12, fontSize: 11, color: "var(--muted)" }}>
                    Next step: generate your DID to get full decentralized identity.
                  </div>
                  <div className="btn-row">
                    <button className="btn btn-accent" onClick={() => setTab("did")}>◆ Generate DID →</button>
                  </div>
                </div>
              ) : (
                <div className="card">
                  <div className="card-title" style={{ marginBottom: 16 }}>New Account</div>
                  <div className="reg-grid">
                    <div className="input-group" style={{ marginBottom: 0 }}>
                      <div className="input-label">Username</div>
                      <input className="input" placeholder="newuser" value={regUsername} onChange={e => setRegUsername(e.target.value)} />
                    </div>
                    <div className="input-group" style={{ marginBottom: 0 }}>
                      <div className="input-label">Password</div>
                      <input className="input" type="password" placeholder="••••••••" value={regPassword} onChange={e => setRegPassword(e.target.value)} />
                    </div>
                  </div>
                  <div className="input-group" style={{ marginTop: 12 }}>
                    <div className="input-label">Server URL</div>
                    <input className="input" value={regServerUrl} onChange={e => setRegServerUrl(e.target.value)} />
                  </div>
                  <div style={{ fontSize: 11, color: "var(--muted)", margin: "12px 0" }}>
                    Flow: Pleroma OAuth app → get token → OS Keychain → Phoenix namespace (PostgreSQL)
                  </div>
                  <button className="btn btn-accent" onClick={handleRegister} disabled={loading}>
                    {loading ? "Registering..." : "⊞ Create Account"}
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Auth */}
          {tab === "auth" && (
            <div className="panel">
              <div className="panel-title">Sign In</div>
              <div className="panel-sub">Token stored in OS Keychain — never written to any file or database</div>

              {auth?.authenticated ? (
                <div className="card">
                  <div className="card-header">
                    <div className="card-title">Authenticated</div>
                    <span className="tag tag-synced">Active</span>
                  </div>
                  {[
                    { k: "Username", v: auth.username ?? "—" },
                    { k: "Server",   v: auth.server_url ?? "—" },
                    { k: "Token",    v: "•••••••••••••• (OS Keychain)" },
                  ].map(r => (
                    <div key={r.k} className="status-row">
                      <span className="status-key">{r.k}</span>
                      <span className="status-val">{r.v}</span>
                    </div>
                  ))}
                  <div className="btn-row">
                    <button className="btn btn-danger" onClick={handleLogout}>Sign Out</button>
                  </div>
                </div>
              ) : (
                <div className="card">
                  <div className="card-title" style={{ marginBottom: 16 }}>Paste Token</div>
                  <div className="input-group">
                    <div className="input-label">OAuth Token</div>
                    <input className="input" placeholder="Bearer token from Pleroma" value={manualToken} onChange={e => setManualToken(e.target.value)} />
                  </div>
                  <div className="input-group">
                    <div className="input-label">Server URL</div>
                    <input className="input" value={manualServer} onChange={e => setManualServer(e.target.value)} />
                  </div>
                  <div className="input-group">
                    <div className="input-label">Username</div>
                    <input className="input" placeholder="your username" value={manualUser} onChange={e => setManualUser(e.target.value)} />
                  </div>
                  <button className="btn btn-accent" onClick={handleManualLogin} disabled={loading}>
                    {loading ? "..." : "→ Sign In"}
                  </button>
                </div>
              )}
            </div>
          )}

          {/* DID */}
          {tab === "did" && (
            <div className="panel">
              <div className="panel-title">Decentralized Identity</div>
              <div className="panel-sub">Ed25519 keypair · private key in OS Keychain · DID links to your namespace</div>

              <div className="btn-row" style={{ marginBottom: 16 }}>
                <button className="btn btn-accent" onClick={handleGenerateDID} disabled={loading}>
                  {loading ? "Generating..." : "◆ Generate New DID"}
                </button>
                <button className="btn" onClick={handleGetDID}>Load Stored DID</button>
                {did && auth?.authenticated && (
                  <button className="btn" onClick={handleLinkDID}>⇢ Link to Namespace</button>
                )}
              </div>

              {did ? (
                <div className="card">
                  <div className="card-header">
                    <div className="card-title">DID Key Pair</div>
                    <span className="tag tag-synced">Active</span>
                  </div>
                  <div className="input-label" style={{ marginBottom: 6 }}>DID Identifier</div>
                  <div className="did-box">{did.did}</div>
                  <div className="input-label" style={{ marginBottom: 6, marginTop: 12 }}>Public Key (Multibase)</div>
                  <div className="did-box" style={{ color: "var(--text)", fontSize: 10 }}>{did.public_key_multibase}</div>
                  <div style={{ marginTop: 12, fontSize: 11, color: "var(--muted)" }}>
                    Private key is in OS Keychain — never leaves this device.<br />
                    Click "Link to Namespace" to attach this DID to your server account (sets identity_type = hybrid).
                  </div>
                </div>
              ) : (
                <div className="empty">
                  <div className="empty-icon">◆</div>
                  <div className="empty-text">No DID loaded.<br />Generate a new one or load from keychain.</div>
                </div>
              )}
            </div>
          )}

          {/* Sync */}
          {tab === "sync" && (
            <div className="panel">
              <div className="panel-title">Sync Engine</div>
              <div className="panel-sub">Tauri → Phoenix → Linode S3 (files) + sqld 172.235.17.68:8080 (metadata)</div>

              <div className="card" style={{ marginBottom: 12 }}>
                <div className="card-header">
                  <div className="card-title">Status</div>
                  <button className="btn btn-sm" onClick={() => { load(); loadOps(); }}>↻</button>
                </div>
                {syncStatus && [
                  { k: "Connection",  v: syncStatus.connection_online ? "Online" : "Offline", c: syncStatus.connection_online ? "green" : "red" },
                  { k: "Syncing",     v: syncStatus.is_syncing ? "Active" : "Idle",            c: syncStatus.is_syncing ? "yellow" : "" },
                  { k: "Last Sync",   v: syncStatus.last_sync_at ?? "Never",                   c: "" },
                  { k: "Pending Ops", v: String(syncStatus.pending_count),                     c: syncStatus.pending_count > 0 ? "yellow" : "green" },
                  { k: "Failed Ops",  v: String(syncStatus.failed_count),                      c: syncStatus.failed_count > 0 ? "red" : "green" },
                ].map(r => (
                  <div key={r.k} className="status-row">
                    <span className="status-key">{r.k}</span>
                    <span className={`status-val ${r.c}`}>{r.v}</span>
                  </div>
                ))}
              </div>

              <div className="btn-row" style={{ marginBottom: 20 }}>
                <button className="btn btn-accent" onClick={handleSync}>↑ Trigger Sync</button>
                <button className="btn" onClick={() => { load(); loadOps(); }}>↻ Refresh</button>
                {(syncStatus?.failed_count ?? 0) > 0 && (
                  <button className="btn btn-danger" onClick={handleRetry}>↻ Retry Failed</button>
                )}
              </div>

              {/* Failed ops */}
              {failedOps.length > 0 && (
                <>
                  <div className="card-title" style={{ marginBottom: 10, color: "var(--accent2)" }}>
                    ✕ Failed ({failedOps.length})
                  </div>
                  {failedOps.map(op => (
                    <div key={op.id} className="op-item">
                      <div className="op-type">{op.op_type}</div>
                      <div className="op-error">{op.error_msg || "Unknown error"}</div>
                      <div className="op-meta">Retries: {op.retry_count} · Doc: {op.doc_id?.slice(0, 20)}…</div>
                    </div>
                  ))}
                  <div className="btn-row"><button className="btn btn-danger" onClick={handleRetry}>↻ Retry All</button></div>
                  <div className="divider" />
                </>
              )}

              {/* Queued ops */}
              {queuedOps.length > 0 && (
                <>
                  <div className="card-title" style={{ marginBottom: 10, color: "var(--warning)" }}>
                    ⏳ Queued ({queuedOps.length})
                  </div>
                  {queuedOps.map(op => (
                    <div key={op.id} className="op-item">
                      <div className="op-type">{op.op_type}</div>
                      <div className="op-meta">Waiting for next sync · Doc: {op.doc_id?.slice(0, 20)}…</div>
                    </div>
                  ))}
                  <div className="divider" />
                </>
              )}

              {failedOps.length === 0 && queuedOps.length === 0 && (
                <div style={{ fontSize: 11, color: "var(--success)", marginBottom: 16 }}>✓ All operations synced</div>
              )}

              <div className="card-title" style={{ marginBottom: 10 }}>Sync Flow</div>
              {[
                "1. Doc created → saved locally in libsql SQLite",
                "2. Queued in sync_operations table",
                "3. Sync engine wakes (30s or manual trigger)",
                "4. GET /sync/upload-url → Phoenix returns S3 presigned URL",
                "5. Tauri PUTs file bytes directly to Linode S3",
                "6. POST /sync/apply → Phoenix writes to PostgreSQL + sqld",
                "7. GET /sync/changes → Tauri pulls latest from sqld",
                "8. Local doc marked is_synced = true",
              ].map((tip, i) => (
                <div key={i} style={{ fontSize: 11, color: "var(--muted)", marginBottom: 6, paddingLeft: 12, borderLeft: "2px solid var(--border)" }}>
                  {tip}
                </div>
              ))}
            </div>
          )}

          {/* Health */}
          {tab === "health" && (
            <div className="panel">
              <div className="panel-title">System Health</div>
              <div className="panel-sub">All layers of the ALEM stack</div>

              {[
                { name: "Tauri App",       status: "running",                                              note: "Desktop process" },
                { name: "Local SQLite",    status: "running",                                              note: "libsql embedded" },
                { name: "Phoenix (4000)",  status: syncStatus?.connection_online ? "online" : "offline",  note: "REST API" },
                { name: "Pleroma (4001)",  status: auth?.authenticated ? "active" : "unknown",            note: "OAuth mock" },
                { name: "PostgreSQL",      status: auth?.authenticated ? "connected" : "unknown",         note: "User metadata + docs" },
                { name: "sqld Linode",     status: syncStatus?.connection_online ? "reachable" : "unknown", note: "172.235.17.68:8080" },
                { name: "S3 Linode",       status: syncedDocs.length > 0 ? "active" : "unknown",          note: "perkeep bucket" },
                { name: "OS Keychain",     status: auth?.authenticated ? "token stored" : "empty",         note: "OAuth + DID key" },
                { name: "DID",             status: did ? "generated" : "not set",                          note: did ? did.did.slice(0, 20) + "…" : "—" },
              ].map(item => (
                <div key={item.name} className="status-row">
                  <span className="status-key">{item.name}</span>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 10, color: "var(--muted)" }}>{item.note}</span>
                    <span className={`tag ${
                      ["running","online","active","connected","reachable","generated","token stored"].includes(item.status)
                        ? "tag-synced"
                        : item.status === "offline" ? "tag-failed"
                        : "tag-local"
                    }`}>{item.status}</span>
                  </div>
                </div>
              ))}

              <div className="btn-row">
                <button className="btn btn-accent" onClick={load}>↻ Refresh</button>
              </div>
            </div>
          )}

        </main>
      </div>

      {/* Toasts */}
      <div className="toast-container">
        {toasts.map(t => (
          <div key={t.id} className={`toast ${t.type}`}>{t.msg}</div>
        ))}
      </div>
    </>
  );
}
