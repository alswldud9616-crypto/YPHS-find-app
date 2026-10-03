import { NextResponse } from 'next/server';
import { requireActor, sameOrigin } from '@/lib/server/auth';
import { db } from '@/lib/server/db';

export async function POST(req: Request) {
  try {
    sameOrigin(req);
    const userId = await requireActor();

    const body = await req.json();
    const endpoint = body?.endpoint;
    const p256dh = body?.keys?.p256dh;
    const auth = body?.keys?.auth;

    if (
      typeof endpoint !== 'string' ||
      typeof p256dh !== 'string' ||
      typeof auth !== 'string'
    ) {
      return NextResponse.json(
        { ok: false, error: '올바르지 않은 푸시 구독 정보예요.' },
        { status: 400 }
      );
    }

    const { error } = await db()
      .from('push_subscriptions')
      .upsert(
        {
          user_id: userId,
          endpoint,
          p256dh,
          auth,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'endpoint' }
      );

    if (error) throw error;

    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json(
      {
        ok: false,
        error: e instanceof Error ? e.message : '푸시 구독에 실패했어요.',
      },
      { status: 400 }
    );
  }
}
