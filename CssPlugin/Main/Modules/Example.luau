return {
 markup=[=[<ui name="CssDemo" data-demo="flex-motion">
  <scroll class="stage">
    <section id="demoCard" class="card">
      <header class="heading">
        <svg id="spark" viewBox="0 0 24 24" fill="currentColor" aria-label="Raio">
          <path id="bolt" d="M13 2 L4 14 H10 L9 22 L20 9 H14 Z">
            <animate attributeName="opacity" values="1;0.45;1" keyTimes="0;0.5;1" dur="1.8s" repeatCount="indefinite" />
            <animateTransform id="boltKick" attributeName="transform" type="translate" values="0 0;0 -2.5;0 0" keyTimes="0;0.4;1" dur="0.35s" begin="click" additive="sum" />
          </path>
        </svg>
        <span class="eyebrow">CSS STUDIO 1.1</span>
        <span id="pulseBadge" class="pulse">EM MOVIMENTO</span>
      </header>
      <h1>Agora a sua UI se move.</h1>
      <p class="description">Adicione itens e redimensione a janela. O motor calcula novas linhas, sem sobrepor os controles.</p>
      <div class="sectionHeading">
        <h2>Uma lista de verdade</h2>
        <span class="codeLabel">flex-wrap: wrap</span>
      </div>
      <section id="tagList" class="tags">
        <span id="chipTemplate" class="chip">Inventário</span>
        <span class="chip">Missões</span>
        <span class="chip">Loja</span>
        <span class="chip">Recompensas</span>
        <span class="chip">Conquistas</span>
        <span class="chip">Amigos</span>
        <span class="chip">Configurações</span>
        <span class="chip">Equipamentos</span>
      </section>
      <p id="wrapStats" class="stats">No Play: itens e linhas são contados em tempo real.</p>
      <div class="actions">
        <button id="wrapAdd">Adicionar item</button>
        <button id="wrapRemove" class="secondary" disabled="true">Remover último</button>
        <button id="motionPause" class="secondary">Pausar animação</button>
      </div>
      <p id="motionStatus" class="description">Passe o mouse nos botões: cor, escala e opacidade mudam suavemente. O selo usa @keyframes.</p>
      <p class="footnote">Snapshot persistente no editor. Movimento no Play, sem depender do plugin.</p>
    </section>
  </scroll>
</ui>]=],
 css=[=[/* CSS Studio 1.1: linhas reais + timelines visuais sem recalcular layout por frame. */
:root {
  --accent: #72b4ff;
  --line: #2d3b50;
  --duration: 180ms;
  color: #edf3ff; font-family: Gotham; font-size: 16px;
}
.stage {
  width: 100%; height: 100%; overflow: auto;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  padding: 24px; background: rgba(7,12,23,0.92);
}
.card {
  width: 720px; max-width: 100%; flex-shrink: 0;
  display: flex; flex-direction: column; gap: 20px;
  padding: 32px; background: #111d2e;
  border: 1px solid var(--line); border-radius: 16px;
  box-shadow: 0px 12px 36px -8px rgba(0,0,0,0.4);
  animation: entrance 450ms ease-out both;
}
.heading { display: flex; flex-flow: row wrap; align-items: center; gap: 12px; }
#spark { width: 28px; height: 28px; color: var(--accent); flex-shrink: 0; }
#bolt:hover { fill: #98f3d5; }
#bolt:active { fill: #ffffff; }
.eyebrow { font-size: 14px; font-weight: 700; color: var(--accent); }
.pulse {
  padding: 6px 10px; font-size: 14px; font-weight: 700;
  background: #1b443c; color: #98f3d5; border-radius: 8px;
  animation: breathe 1200ms ease-in-out infinite alternate;
}
.pulse.paused { animation-play-state: paused; }
h1 { font-size: 32px; font-weight: 700; }
h2 { font-size: 18px; font-weight: 700; }
.description { color: #b8c7dc; font-size: 16px; }
.sectionHeading { display: flex; flex-flow: row wrap; align-items: center; justify-content: space-between; gap: 8px; }
.codeLabel { font-family: monospace; font-size: 14px; color: #b7d9ff; }
.tags {
  display: flex; flex-direction: row; flex-wrap: wrap;
  align-items: flex-start; align-content: flex-start;
  column-gap: 8px; row-gap: 10px;
  padding: 16px; background: #0c1523;
  border: 1px solid var(--line); border-radius: 12px;
}
.chip {
  flex: 0 0 auto; max-width: 100%;
  height: 36px; padding: 8px 12px;
  background: #20344e; color: #d0e4ff;
  font-size: 14px; white-space: nowrap; border-radius: 8px;
}
.stats { font-size: 14px; color: #b7d9ff; min-height: 20px; }
.actions { display: flex; flex-flow: row wrap; gap: 12px; }
button {
  flex: 1 1 180px; min-width: 150px; height: 48px;
  padding: 12px; background: var(--accent); color: #07101e;
  font-size: 14px; font-weight: 700; border-radius: 8px;
  transition: background-color var(--duration) ease-out,
              transform var(--duration) ease-out,
              opacity var(--duration) linear;
}
button:hover { background-color: #a1cfff; transform: scale(1.025); }
button:active { background-color: #5392e9; transform: scale(0.97); }
button:focus { border: 2px solid #ffffff; }
.secondary { background: #263c58; color: #edf3ff; }
.secondary:hover { background-color: #355776; }
.secondary:active { background-color: #1d2d43; }
button:disabled { opacity: 0.5; transform: scale(1); }
.footnote { font-size: 14px; color: #a9bbd2; }
@keyframes entrance {
  from { opacity: 0; transform: scale(0.96); }
  to { opacity: 1; transform: scale(1); }
}
@keyframes breathe {
  0% { opacity: 0.72; transform: scale(0.98); }
  100% { opacity: 1; transform: scale(1.03); }
}
@media (max-width: 620px) {
  .stage { padding: 16px; }
  .card { width: 100%; padding: 20px; gap: 16px; }
  h1 { font-size: 26px; }
  .tags { padding: 12px; }
}
]=]
}
