return {
 markup=[=[<ui name="CssDemo" data-demo="counter">
  <main class="stage">
    <section class="card">
      <header class="heading">
        <svg id="spark" viewBox="0 0 24 24" fill="currentColor" aria-label="Raio">
          <path d="M13 2 L4 14 H10 L9 22 L20 9 H14 Z" />
        </svg>
        <span class="eyebrow">CSS STUDIO / INTERFACE REAL</span>
      </header>
      <h1>Do código para o jogo.</h1>
      <p class="description">HTML, CSS e SVG viram objetos no Explorer. O texto continua editável e os botões continuam interativos.</p>
      <div class="features">
        <section class="feature">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <path d="M8 6 L2 12 L8 18 M16 6 L22 12 L16 18 M14 4 L10 20" />
          </svg>
          <p>Autoria em código</p>
        </section>
        <section class="feature">
          <svg viewBox="0 0 24 24" fill="currentColor" fill-rule="evenodd">
            <path d="M12 2 A10 10 0 1 1 12 22 A10 10 0 1 1 12 2 Z M12 7 A5 5 0 1 0 12 17 A5 5 0 1 0 12 7 Z" />
          </svg>
          <p>SVG com recortes</p>
        </section>
      </div>
      <input id="playerName" placeholder="Digite seu nome (opcional)" />
      <div class="actions">
        <button id="launch">Testar interação</button>
        <button id="toggle" class="secondary">Desabilitar</button>
      </div>
      <p id="status">No Play, clique em Testar interação.</p>
      <p class="footnote">Salve o place. A aparência gerada não precisa do plugin.</p>
    </section>
  </main>
</ui>]=],
 css=[=[/* Subconjunto explícito; todos os tamanhos usam border-box. */
:root {
  --accent: #72b4ff;
  --line: #2d3b50;
  color: #edf3ff;
  font-family: Gotham;
  font-size: 16px;
}
.stage {
  width: 100%; height: 100%;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  background: rgba(7, 12, 23, 0.88);
  padding: 24px;
}
.card {
  width: 600px; max-width: 100%;
  display: flex; flex-direction: column; gap: 20px;
  padding: 32px;
  background: #111d2e;
  border: 1px solid var(--line); border-radius: 20px;
  box-shadow: 0px 18px 48px -8px rgba(0,0,0,0.5);
  flex-shrink: 0;
}
.heading { display: flex; flex-direction: row; align-items: center; gap: 12px; }
#spark { width: 32px; height: 32px; color: var(--accent); flex-shrink: 0; }
.eyebrow { font-size: 14px; font-weight: 700; color: var(--accent); }
h1 { font-size: 32px; font-weight: 700; }
.description { color: #b0bfd4; font-size: 16px; }
.features { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
.feature {
  display: flex; flex-direction: row; align-items: center; gap: 12px;
  background: #19283c; border-radius: 10px; padding: 16px;
}
.feature svg { width: 24px; height: 24px; color: var(--accent); flex-shrink: 0; }
.feature p { font-size: 14px; }
input {
  height: 48px; padding: 12px 16px;
  background: #0c1523; border: 1px solid var(--line); border-radius: 10px;
}
input:focus { border-color: var(--accent); }
.actions { display: flex; flex-direction: row; gap: 12px; }
button {
  height: 48px; padding: 12px; flex-grow: 1; flex-basis: 0px;
  background: linear-gradient(110deg, #72b4ff 0%, #4e8be8 100%);
  color: #07101e; font-weight: 700; border-radius: 10px;
}
button:hover { background: #94c6ff; }
button:focus { border: 2px solid #ffffff; }
button:active { background: #5392e9; }
button:disabled { background: #324257; color: #abb8c9; }
.secondary { background: #23354d; color: #edf3ff; }
.secondary:hover { background: #304a69; }
#status { font-size: 14px; color: #b7d9ff; min-height: 20px; }
.footnote { font-size: 14px; color: #a5b6ce; }
@media (max-width: 620px) {
  .stage { padding: 16px; }
  .card { width: 100%; padding: 20px; gap: 16px; }
  h1 { font-size: 26px; }
  .features { grid-template-columns: 1fr; }
  .actions { flex-direction: column; }
  button { flex-basis: auto; flex-shrink: 0; }
}
]=]
}
