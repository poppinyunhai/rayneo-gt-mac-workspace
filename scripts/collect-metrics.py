"""Sample local runtime diagnostics; never reads screen images or uploads data."""
from pathlib import Path
import argparse,csv,json,time,datetime
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--duration',type=int,default=60)
parser.add_argument('--status',type=Path,default=Path.home()/'Library/Application Support/RayNeoWorkspace-Dev/runtime-status.json')
parser.add_argument('--output',type=Path)
args=parser.parse_args()
if args.duration<1: parser.error('duration must be positive')
output=args.output or Path(__file__).resolve().parents[1]/'build'/('metrics-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.csv')
output.parent.mkdir(parents=True,exist_ok=True)
columns=['elapsed_s','state','cpu_percent','resident_mb','fps_left','fps_center','fps_right','delivery_ms','source_age_ms','merged_frames','gpu_frames','fallback_frames','yaw_deg','bias_y_dps','temperature','status']
previous=None;started=time.monotonic();valid=0
with output.open('w',newline='') as handle:
    writer=csv.DictWriter(handle,fieldnames=columns);writer.writeheader()
    while time.monotonic()-started<args.duration:
        try:
            state=json.loads(args.status.read_text())
            process=state.get('process',{});capture=state.get('capture',[]);imu=state.get('imu',{})
            uptime=process.get('uptimeSeconds',0)
            if previous and uptime==previous[0]: time.sleep(0.2);continue
            fps=[0.0,0.0,0.0]
            if previous:
                dt=uptime-previous[0]
                same_ids=state.get('virtualIDs')==previous[2]
                if 0<dt<3 and same_ids:
                    for index,item in enumerate(capture[:3]):
                        old=previous[1][index] if index<len(previous[1]) else item['frames']
                        fps[index]=max(0,(item['frames']-old)/dt)
            mean=lambda field: sum(x.get(field,0) for x in capture)/max(1,len(capture))
            row=dict(elapsed_s=round(time.monotonic()-started,2),state=state.get('sessionState'),cpu_percent=process.get('cpuPercent'),resident_mb=process.get('residentMB'),
                     fps_left=fps[0],fps_center=fps[1],fps_right=fps[2],delivery_ms=mean('deliveryMS'),source_age_ms=mean('sourceAgeMS'),
                     merged_frames=sum(x.get('mergedFrames',0) for x in capture),gpu_frames=sum(x.get('gpuFrames',0) for x in capture),fallback_frames=sum(x.get('fallbackFrames',0) for x in capture),
                     yaw_deg=imu.get('yawDegrees'),bias_y_dps=imu.get('biasDPS',[0,0,0])[1],temperature=imu.get('temperature'),status=state.get('status'))
            writer.writerow(row);handle.flush();valid+=1
            previous=(uptime,[x['frames'] for x in capture],state.get('virtualIDs'))
        except (OSError,ValueError,KeyError,IndexError) as error:
            if valid==0: print('Waiting for app telemetry:',type(error).__name__)
        time.sleep(1)
print('Saved',valid,'samples to',output)
if valid==0: raise SystemExit('No telemetry collected; start the development app before profiling.')
