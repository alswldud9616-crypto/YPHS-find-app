import type { Metadata } from 'next';
import '@fontsource/gowun-dodum/400.css';
import '@fontsource/noto-sans-kr/400.css';
import '@fontsource/noto-sans-kr/700.css';
import './globals.css';
import { AppProvider } from '@/components/provider';
export const metadata:Metadata={title:'양고 찾기 | 양평고등학교',description:'양평고등학교 분실물 안내',icons:{icon:'/favicon.svg'}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="ko"><body><AppProvider>{children}</AppProvider></body></html>}
