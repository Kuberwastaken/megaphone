import React from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

type Demo = {
  app: 'Claude Code' | 'Codex' | 'Obsidian';
  accent: string;
  prompt: string;
  output: string;
};

const demos: Demo[] = [
  {
    app: 'Claude Code',
    accent: '#d97757',
    prompt: 'Can you, um, add a shortcut to open settings and update the tests?',
    output: 'Add a keyboard shortcut to open Settings and update the tests.',
  },
  {
    app: 'Codex',
    accent: '#7c9cff',
    prompt: 'Find the, the race condition in the updater and make the rollback safe.',
    output: 'Find the race condition in the updater and make the rollback safe.',
  },
  {
    app: 'Obsidian',
    accent: '#9b7cff',
    prompt: 'Meeting notes, um, ship the beta on Thursday—no, Wednesday afternoon.',
    output: '## Meeting notes\n\nShip the beta on Wednesday afternoon.',
  },
];

const colors = {
  desktop: '#cbd4dd',
  chrome: '#f4f4f3',
  border: 'rgba(20, 24, 31, 0.13)',
  ink: '#202126',
  muted: '#777b84',
};

const WindowChrome: React.FC<React.PropsWithChildren<{demo: Demo}>> = ({demo, children}) => (
  <div
    style={{
      position: 'absolute',
      inset: '48px 56px 46px',
      borderRadius: 17,
      overflow: 'hidden',
      background: demo.app === 'Obsidian' ? '#fafafa' : '#15161a',
      boxShadow: '0 30px 75px rgba(29, 39, 55, .24), 0 2px 10px rgba(0,0,0,.12)',
      border: `1px solid ${colors.border}`,
    }}
  >
    <div
      style={{
        height: 48,
        background: colors.chrome,
        borderBottom: `1px solid ${colors.border}`,
        display: 'flex',
        alignItems: 'center',
        padding: '0 17px',
        color: '#575a61',
        fontSize: 13,
        fontWeight: 600,
      }}
    >
      <div style={{display: 'flex', gap: 8, marginRight: 18}}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <span key={c} style={{width: 12, height: 12, borderRadius: 12, background: c}} />
        ))}
      </div>
      <span style={{color: demo.accent, fontSize: 16, marginRight: 8}}>●</span>
      {demo.app}
      <span style={{marginLeft: 'auto', color: '#999ca3', fontWeight: 500}}>Megaphone demo</span>
    </div>
    {children}
  </div>
);

const Terminal: React.FC<{demo: Demo; typed: string; cursor: boolean}> = ({demo, typed, cursor}) => (
  <div style={{height: '100%', padding: '44px 54px', color: '#e8e9ed', fontFamily: 'SFMono-Regular, Menlo, monospace'}}>
    <div style={{color: '#7d818b', fontSize: 18, marginBottom: 34}}>~/dev/megaphone &nbsp; main</div>
    <div style={{display: 'flex', gap: 16, lineHeight: 1.5, fontSize: 27, fontWeight: 540}}>
      <span style={{color: demo.accent}}>❯</span>
      <span>
        {typed}
        {cursor && <span style={{display: 'inline-block', width: 10, height: 22, background: demo.accent, verticalAlign: -4, marginLeft: 3}} />}
      </span>
    </div>
    <div style={{marginTop: 54, borderTop: '1px solid #2d2f35', paddingTop: 22, color: '#777b84', fontSize: 17}}>
      {demo.app === 'Claude Code' ? 'Claude can make mistakes. Please review changes.' : 'Local workspace · full context'}
    </div>
  </div>
);

const Obsidian: React.FC<{typed: string; cursor: boolean}> = ({typed, cursor}) => (
  <div style={{height: '100%', display: 'flex', color: colors.ink}}>
    <aside style={{width: 218, background: '#f1f1f0', borderRight: `1px solid ${colors.border}`, padding: '28px 20px'}}>
      <div style={{fontWeight: 700, fontSize: 15, marginBottom: 30}}>Megaphone</div>
      <div style={{fontSize: 13, color: colors.muted, lineHeight: 2.25}}>▾ Notes<br />&nbsp;&nbsp; Today<br />&nbsp;&nbsp; Product ideas<br />&nbsp;&nbsp; Meeting notes</div>
    </aside>
    <main style={{flex: 1, padding: '58px 76px', fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'}}>
      <div style={{fontSize: 14, color: '#999', marginBottom: 26}}>Meeting notes</div>
      <div style={{whiteSpace: 'pre-wrap', fontSize: 28, lineHeight: 1.55, fontWeight: 560}}>
        {typed}
        {cursor && <span style={{display: 'inline-block', height: 31, width: 2, background: '#6f52d9', verticalAlign: -5, marginLeft: 2}} />}
      </div>
    </main>
  </div>
);

const Waveform: React.FC<{frame: number}> = ({frame}) => (
  <div style={{display: 'flex', height: 24, alignItems: 'center', gap: 2.5}}>
    {Array.from({length: 9}, (_, i) => {
      const envelope = Math.sin(((i + 1) / 10) * Math.PI);
      const motion = Math.abs(Math.sin(frame * 0.37 + i * 1.73));
      const h = 3 + envelope * (6 + motion * 15);
      return <span key={i} style={{width: 3, height: h, borderRadius: 3, background: '#fff', opacity: 0.58 + motion * 0.42}} />;
    })}
  </div>
);

const ProcessingWave: React.FC<{frame: number}> = ({frame}) => (
  <div style={{display: 'flex', height: 20, alignItems: 'center', gap: 4}}>
    {Array.from({length: 5}, (_, i) => {
      const pulse = 0.5 + 0.5 * Math.sin(frame * 0.22 - i * 0.72);
      return <span key={i} style={{width: 3, height: 4 + pulse * 14, borderRadius: 3, background: '#fff', opacity: 0.42 + pulse * 0.52}} />;
    })}
  </div>
);

const MegaphoneOverlay: React.FC<{frame: number; active: boolean}> = ({frame, active}) => {
  const {fps} = useVideoConfig();
  const safeFrame = Math.max(0, frame);
  const entry = spring({frame: safeFrame, fps, config: {damping: 17, stiffness: 185, mass: 0.75}});
  const exit = interpolate(safeFrame, [75, 86], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.in(Easing.cubic)});
  const processing = safeFrame >= 60;
  const width = interpolate(safeFrame, [58, 68], [118, 104], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic)});

  return (
    <div
      style={{
        position: 'absolute',
        top: -2,
        left: '50%',
        width,
        height: 44,
        transform: `translateX(-50%) translateY(${interpolate(entry, [0, 1], [-50, 0])}px) scale(${0.92 + entry * 0.08})`,
        opacity: entry * exit,
        borderRadius: '0 0 16px 16px',
        background: '#050506',
        boxShadow: '0 10px 28px rgba(0,0,0,.32), inset 0 -1px rgba(255,255,255,.06)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 20,
      }}
    >
      {!processing && active ? <Waveform frame={safeFrame} /> : <ProcessingWave frame={safeFrame} />}
    </div>
  );
};

const AppScene: React.FC<{demo: Demo}> = ({demo}) => {
  const frame = useCurrentFrame();
  const outputStart = 72;
  const chars = Math.floor(interpolate(frame, [outputStart, 91], [0, demo.output.length], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
  const typed = demo.output.slice(0, chars);
  // Keep the app visible on frame zero so README/GitHub GIF previews have a
  // useful poster frame; the Megaphone overlay itself still animates in.
  const sceneIn = 1;
  const sceneOut = interpolate(frame, [111, 120], [1, 0], {extrapolateLeft: 'clamp', easing: Easing.in(Easing.cubic)});
  const captionIn = interpolate(frame, [12, 20], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const captionOut = interpolate(frame, [58, 67], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill style={{opacity: sceneIn * sceneOut, transform: `scale(${1.015 - sceneIn * 0.015 + (1 - sceneOut) * 0.015})`}}>
      <WindowChrome demo={demo}>
        {demo.app === 'Obsidian' ? <Obsidian typed={typed} cursor={frame >= outputStart} /> : <Terminal demo={demo} typed={typed} cursor={frame >= outputStart} />}
      </WindowChrome>
      <MegaphoneOverlay frame={frame - 8} active={frame < 60} />
      <div
        style={{
          position: 'absolute',
          bottom: 49,
          left: '50%',
          transform: `translateX(-50%) translateY(${(1 - captionIn) * 6}px)`,
          opacity: captionIn * captionOut,
          maxWidth: 820,
          padding: '10px 17px',
          borderRadius: 14,
          background: 'rgba(247,249,251,.9)',
          border: '1px solid rgba(30,38,48,.1)',
          boxShadow: '0 8px 24px rgba(34,45,60,.12)',
          color: '#535a64',
          fontSize: 17,
          fontWeight: 540,
          whiteSpace: 'nowrap',
        }}
      >
        <span style={{color: demo.accent, marginRight: 9}}>●</span>
        “{demo.prompt}”
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 16,
          left: '50%',
          transform: 'translateX(-50%)',
          color: 'rgba(31,38,48,.65)',
          fontSize: 13,
          fontWeight: 650,
          letterSpacing: '.02em',
        }}
      >
        Hold Fn · speak · release
      </div>
    </AbsoluteFill>
  );
};

export const MegaphoneIntro: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(circle at 50% 10%, #edf2f6 0, ${colors.desktop} 72%)`,
      fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif',
    }}
  >
    {demos.map((demo, i) => (
      <Sequence key={demo.app} from={i * 120} durationInFrames={120} premountFor={15}>
        <AppScene demo={demo} />
      </Sequence>
    ))}
  </AbsoluteFill>
);
