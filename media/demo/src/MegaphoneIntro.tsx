import React from 'react';
import {
  AbsoluteFill,
  Easing,
  OffthreadVideo,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';

const fps = 30;
const playbackRate = 1.35;
const transitionFrames = 6;

type Scene = {
  name: string;
  sourceStart: number;
  sourceEnd: number;
  timelineStart: number;
  duration: number;
};

const sourceScenes = [
  {name: 'Claude Code', sourceStart: 0, sourceEnd: 4},
  {name: 'Codex', sourceStart: 4.05, sourceEnd: 9},
  {name: 'Cursor CLI', sourceStart: 9.25, sourceEnd: 14.5},
  {name: 'Google Docs', sourceStart: 14.7, sourceEnd: 21.48},
];

let nextTimelineStart = 0;
export const scenes: Scene[] = sourceScenes.map((scene) => {
  const duration = Math.round(((scene.sourceEnd - scene.sourceStart) / playbackRate) * fps);
  const result = {...scene, duration, timelineStart: nextTimelineStart};
  nextTimelineStart += duration - transitionFrames;
  return result;
});

export const demoDuration = nextTimelineStart + transitionFrames;

const DemoScene: React.FC<{scene: Scene; index: number}> = ({scene, index}) => {
  const frame = useCurrentFrame();
  const fadeIn = index === 0
    ? 1
    : interpolate(frame, [0, transitionFrames], [0, 1], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      });
  const fadeOut = interpolate(
    frame,
    [scene.duration - transitionFrames, scene.duration],
    [1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );

  let scale = 1;
  if (index === 0) {
    const zoomIn = interpolate(frame, [4, 23], [1, 1.5], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.inOut(Easing.cubic),
    });
    const zoomOut = interpolate(frame, [56, 82], [1.5, 1], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.inOut(Easing.cubic),
    });
    scale = frame < 56 ? zoomIn : zoomOut;
  } else {
    // A nearly imperceptible push keeps static screen captures feeling alive
    // without making the real app switching look synthetic.
    scale = interpolate(frame, [0, scene.duration], [1.008, 1.025], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.inOut(Easing.cubic),
    });
  }

  return (
    <AbsoluteFill style={{opacity: fadeIn * fadeOut, overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          transform: `scale(${scale})`,
          transformOrigin: index === 0 ? '50% 0%' : '50% 45%',
          willChange: 'transform',
        }}
      >
        <OffthreadVideo
          src={staticFile('latest-demo.mp4')}
          startFrom={Math.round(scene.sourceStart * fps)}
          playbackRate={playbackRate}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const MegaphoneIntro: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: '#0b0e10'}}>
    {scenes.map((scene, index) => (
      <Sequence
        key={scene.name}
        from={scene.timelineStart}
        durationInFrames={scene.duration}
        premountFor={15}
      >
        <DemoScene scene={scene} index={index} />
      </Sequence>
    ))}
  </AbsoluteFill>
);
