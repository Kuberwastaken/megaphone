import React from 'react';
import {AbsoluteFill, OffthreadVideo, staticFile} from 'remotion';

export const demoDuration = 418;

export const MegaphoneIntro: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: '#0b0e10'}}>
    <OffthreadVideo
      src={staticFile('latest-demo.mp4')}
      muted
      style={{width: '100%', height: '100%', objectFit: 'cover'}}
    />
  </AbsoluteFill>
);
