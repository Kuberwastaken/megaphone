import React from 'react';
import {
  AbsoluteFill,
  Easing,
  OffthreadVideo,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';

const zoomInEnd = 18;
const zoomOutStart = 49;
const zoomOutEnd = 70;

export const MegaphoneIntro: React.FC = () => {
  const frame = useCurrentFrame();

  const zoomIn = interpolate(frame, [2, zoomInEnd], [1, 1.5], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const zoomOut = interpolate(frame, [zoomOutStart, zoomOutEnd], [1.5, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const scale = frame < zoomOutStart ? zoomIn : zoomOut;

  return (
    <AbsoluteFill style={{backgroundColor: '#101315', overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          transform: `scale(${scale})`,
          transformOrigin: '50% 0%',
          willChange: 'transform',
        }}
      >
        <OffthreadVideo
          src={staticFile('original-demo.mp4')}
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
