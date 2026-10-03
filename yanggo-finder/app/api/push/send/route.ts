import { NextResponse } from 'next/server';
import webpush from 'web-push';
import { requireActor, sameOrigin } from '@/lib/server/auth';
import { db } from '@/lib/server/db';

export async function POST(req: Request) {
  try {
    sameOrigin(req);
    const userId = await requireActor();

    const publicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
    const privateKey = process.env.VAPID_PRIVATE_KEY;

    if (!publicKey || !privateKey) {
      throw new Error('VAPID 환경변수가 설정되지 않았어요.');
    }

    webpush.setVapidDetails(
      'mailto:admin@yphs-finder.local',
      publicKey,
      privateKey
    );

    const { data, error } = await db()
      .from('push_subscriptions')
      .select('id,endpoint,p256dh,auth')
      .eq('user_id', userId);

    if (error) throw error;

    let sent = 0;

    for (const sub of data ?? []) {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: {
              p256dh: sub.p256dh,
              auth: sub.auth,
            },
          },
          JSON.stringify({
            title: '양고 찾기',
            body: '휴대폰 알림 연결이 완료됐어요! 🔔',
            url: '/notifications',
          })
        );
        sent++;
      } catch (e: any) {
        if (e?.statusCode === 404 || e?.statusCode === 410) {
          await db()
            .from('push_subscriptions')
            .delete()
            .eq('id', sub.id);
        }
      }
    }

    return NextResponse.json({ ok: true, sent });
  } catch (e) {
    return NextResponse.json(
      {
        ok: false,
        error: e instanceof Error ? e.message : '알림 발송에 실패했어요.',
      },
      { status: 400 }
    );
  }
}
