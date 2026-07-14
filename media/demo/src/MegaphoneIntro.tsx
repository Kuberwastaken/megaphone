import React from 'react';
import {
  AbsoluteFill,
  Easing,
  OffthreadVideo,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';

export const demoDuration = 645;

export const MegaphoneIntro: React.FC = () => {
  const frame = useCurrentFrame();

  // Match the earlier real-screen demo: a smooth, top-anchored 50% push
  // toward Megaphone while Claude Code is recording, then return to the
  // untouched capture early enough to hold on the finished output.
  const zoomIn = interpolate(frame, [4, 26], [1, 1.5], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const zoomOut = interpolate(frame, [56, 84], [1.5, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const scale = frame < 56 ? zoomIn : zoomOut;

  return (
    <AbsoluteFill style={{backgroundColor: '#0b0e10', overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          transform: `scale(${scale})`,
          transformOrigin: '50% 0%',
          willChange: 'transform',
        }}
      >
        <OffthreadVideo
          src={staticFile('latest-demo.mp4')}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
