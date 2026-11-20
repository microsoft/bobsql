import React from 'react';
import ReactDOM from 'react-dom/client';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';
import { App } from './App.tsx';
import './styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <FluentProvider theme={{
      ...webLightTheme,
      fontFamilyBase: '"Segoe UI", system-ui, sans-serif',
      fontSizeBase300: '18px', lineHeightBase300: '26px',
      fontSizeBase200: '18px', lineHeightBase200: '26px',
      colorBrandBackground: '#0078D4',
      colorBrandBackgroundHover: '#005A9E',
      colorBrandBackgroundPressed: '#004578',
      colorBrandBackgroundSelected: '#005A9E',
      colorBrandForeground1: '#005A9E',
      colorBrandForeground2: '#005A9E',
      colorBrandStroke1: '#0078D4',
      colorCompoundBrandBackground: '#0078D4',
      colorCompoundBrandBackgroundHover: '#005A9E',
      colorCompoundBrandStroke: '#0078D4',
    }}>
      <App />
    </FluentProvider>
  </React.StrictMode>,
);
