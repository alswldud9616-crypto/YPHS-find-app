const origin=process.env.APP_ORIGIN,secret=process.env.CRON_SECRET;if(!origin||!secret)throw Error('APP_ORIGIN and CRON_SECRET required');
const result=await fetch(new URL('/api/maintenance',origin),{headers:{Authorization:'Bearer '+secret}});if(!result.ok)throw Error('Maintenance failed: '+result.status);console.log(await result.json());
