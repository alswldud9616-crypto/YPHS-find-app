'use client';

import { useState } from 'react';

function urlBase64ToUint8Array(base64String: string) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  const rawData = window.atob(base64);

  return Uint8Array.from([...rawData].map(char => char.charCodeAt(0)));
}

export default function PushButton() {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  async function enablePush() {
    try {
      setBusy(true);
      setMessage('');

      if (
        !('serviceWorker' in navigator) ||
        !('PushManager' in window) ||
        !('Notification' in window)
      ) {
        throw new Error('이 기기에서는 푸시 알림을 사용할 수 없어요.');
      }

      const permission = await Notification.requestPermission();

      if (permission !== 'granted') {
        throw new Error('알림 권한을 허용해주세요.');
      }

      const registration = await navigator.serviceWorker.ready;

      let subscription =
        await registration.pushManager.getSubscription();

      if (!subscription) {
        const publicKey =
          process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

        if (!publicKey) {
          throw new Error('푸시 공개키가 설정되지 않았어요.');
        }

        subscription =
          await registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey:
              urlBase64ToUint8Array(publicKey),
          });
      }

      const save = await fetch('/api/push/subscribe', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(subscription.toJSON()),
      });

      const saveResult = await save.json();

      if (!save.ok) {
        throw new Error(
          saveResult.error || '알림 등록에 실패했어요.'
        );
      }

      const test = await fetch('/api/push/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: '{}',
      });

      const testResult = await test.json();

      if (!test.ok) {
        throw new Error(
          testResult.error || '테스트 알림 발송에 실패했어요.'
        );
      }

      setMessage(
        testResult.sent > 0
          ? '휴대폰 알림을 켰어요. 테스트 알림을 확인해주세요!'
          : '알림은 켜졌지만 테스트 알림을 보내지 못했어요.'
      );
    } catch (e) {
      setMessage(
        e instanceof Error
          ? e.message
          : '알림 설정 중 오류가 발생했어요.'
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{ marginTop: 12 }}>
      <button
        type="button"
        className="button"
        disabled={busy}
        onClick={enablePush}
      >
        {busy ? '알림 연결 중...' : '🔔 휴대폰 알림 켜기'}
      </button>

      {message && (
        <p className="small muted" style={{ marginTop: 8 }}>
          {message}
        </p>
      )}
    </div>
  );
}
