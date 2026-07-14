import React from 'react';
import {
  AbsoluteFill,
  Easing,
  OffthreadVideo,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';

const zoomInEnd = 13;
const zoomOutStart = 49;
const zoomOutEnd = 70;

export const MegaphoneIntro: React.FC = () => {
  const frame = useCurrentFrame();

  const zoomIn = interpolate(frame, [2, zoomInEnd], [1, 1.13], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const zoomOut = interpolate(frame, [zoomOutStart, zoomOutEnd], [1.13, 1], {
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
          transformOrigin: '50% 7%',
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
