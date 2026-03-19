

!pip install openpyxl -q

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import matplotlib.patches as mpatches
from matplotlib.colors import LinearSegmentedColormap
import seaborn as sns
import warnings
warnings.filterwarnings('ignore')

plt.rcParams.update({'figure.dpi': 130, 'axes.spines.top': False,
                     'axes.spines.right': False, 'font.family': 'DejaVu Sans'})

C = {'red':'#E24B4A','blue':'#378ADD','green':'#1D9E75',
     'amber':'#BA7517','purple':'#7F77DD','gray':'#888780','dark':'#0C447C'}
print('Libraries loaded successfully')
# CELL 2: Upload and load the dataset
# Run this cell, then click 'Choose Files' and upload finance_shipments.csv

from google.colab import files
uploaded = files.upload()  # Click 'Choose Files' -> select finance_shipments.csv

df = pd.read_csv('/content/finance_shipments.csv', parse_dates=['ship_date','delivery_date'])
df['month'] = df['ship_date'].dt.to_period('M').astype(str)
df['year']  = df['ship_date'].dt.year

print(f'Dataset loaded: {len(df):,} rows x {df.shape[1]} columns')
print(f'Carriers: {df["carrier"].nunique()} | Regions: {df["region"].nunique()}')
print(f'Date range: {df["ship_date"].min().date()} to {df["ship_date"].max().date()}')
df.head(3)
# CELL 3: KPI Summary (Platform-wide health check)
kpis = {
    'Total Shipments':     len(df),
    'Active Carriers':     df['carrier'].nunique(),
    'Active Regions':      df['region'].nunique(),
    'Avg Freight Cost ($)':round(df['freight_cost_usd'].mean(), 2),
    'On-Time Rate (%)':    round((~df['is_late']).mean()*100, 2),
    'Late Shipments':      int(df['is_late'].sum()),
    'Damage Rate (%)':     round(df['is_damaged'].mean()*100, 2),
    'Total Shipment Value ($)': round(df['shipment_value_usd'].sum(), 2)
}
kpi_df = pd.DataFrame(list(kpis.items()), columns=['KPI','Value'])
print('=== PLATFORM KPI SUMMARY ===')
print(kpi_df.to_string(index=False))
# CELL 4: Carrier Performance Benchmarking
carrier_perf = (
    df.groupby('carrier')
    .agg(total=('shipment_id','count'), late=('is_late','sum'),
         damaged=('is_damaged','sum'), avg_cost=('freight_cost_usd','mean'),
         avg_days=('delivery_days','mean'), total_val=('shipment_value_usd','sum'))
    .assign(
        on_time_pct=lambda x: ((1-x['late']/x['total'])*100).round(1),
        damage_pct=lambda x:  (x['damaged']/x['total']*100).round(2),
        avg_cost=lambda x:    x['avg_cost'].round(2),
        avg_days=lambda x:    x['avg_days'].round(1)
    ).reset_index()
)
carrier_perf['score'] = (
    carrier_perf['on_time_pct']*0.5
    - carrier_perf['damage_pct']*0.3
    - carrier_perf['avg_cost'].rank(pct=True)*20
).round(1)
carrier_perf['tier'] = carrier_perf['score'].apply(
    lambda x: 'Preferred' if x>=35 else ('Acceptable' if x>=20 else ('Monitor' if x>=10 else 'Review')))
carrier_perf = carrier_perf.sort_values('score', ascending=False).reset_index(drop=True)
print(carrier_perf[['carrier','on_time_pct','avg_cost','score','tier']].to_string(index=False))
# CELL 5: Cost Anomaly Detection (MoM delta — window function equivalent)
monthly_cost = (
    df.groupby(['carrier','month'])['freight_cost_usd']
    .mean().round(2).reset_index().sort_values(['carrier','month'])
)
monthly_cost['prev_cost']       = monthly_cost.groupby('carrier')['freight_cost_usd'].shift(1)
monthly_cost['cost_change_pct'] = (
    (monthly_cost['freight_cost_usd'] - monthly_cost['prev_cost'])
    / monthly_cost['prev_cost'].replace(0, np.nan) * 100
).round(2)
monthly_cost['anomaly_flag'] = monthly_cost['cost_change_pct'].apply(
    lambda x: 'CRITICAL SPIKE' if pd.notnull(x) and x>20
    else ('Anomaly — Review' if pd.notnull(x) and x>10
    else ('Significant Drop' if pd.notnull(x) and x<-10 else 'Normal')))

anomalies = monthly_cost[monthly_cost['anomaly_flag'].isin(['CRITICAL SPIKE','Anomaly — Review'])]
print(f'Total anomalies detected: {len(anomalies)}')
print(f'Critical spikes: {(monthly_cost["anomaly_flag"]=="CRITICAL SPIKE").sum()}')
print(anomalies.sort_values('cost_change_pct', ascending=False).head(10).to_string(index=False))
# CELL 6: DASHBOARD 1 — Carrier Benchmarking
fig = plt.figure(figsize=(18,12))
fig.patch.set_facecolor('#F8F9FA')
gs  = gridspec.GridSpec(3,3,figure=fig,hspace=0.45,wspace=0.35)

for i,(lbl,val,col,bg) in enumerate([
    ('Total Shipments',f'{len(df):,}',C['blue'],'#E6F1FB'),
    ('On-Time Rate', f'{(~df["is_late"]).mean()*100:.1f}%',C['green'],'#EAF3DE'),
    ('Avg Freight Cost',f'${df["freight_cost_usd"].mean():.0f}',C['amber'],'#FAEEDA')]):
    ax=fig.add_subplot(gs[0,i]); ax.set_facecolor(bg); ax.axis('off')
    ax.set_xlim(0,1); ax.set_ylim(0,1)
    ax.add_patch(mpatches.FancyBboxPatch((0.05,0.05),0.9,0.9,
        boxstyle='round,pad=0.02',facecolor=bg,edgecolor=col,linewidth=2.5))
    ax.text(0.5,0.65,val,ha='center',va='center',fontsize=26,fontweight='bold',color=col)
    ax.text(0.5,0.25,lbl,ha='center',va='center',fontsize=11,color='#444441')

ax2=fig.add_subplot(gs[1,:2]); ax2.set_facecolor('white')
cp=carrier_perf.sort_values('score',ascending=True)
tier_c={'Preferred':C['green'],'Acceptable':C['blue'],'Monitor':C['amber'],'Review':C['red']}
bcolors=[tier_c.get(t,C['gray']) for t in cp['tier']]
bars=ax2.barh(cp['carrier'],cp['score'],color=bcolors,height=0.65)
ax2.set_xlabel('Composite Score'); ax2.set_title('Carrier Performance Benchmark',fontsize=12,fontweight='bold',pad=8)
for bar,val,tier in zip(bars,cp['score'],cp['tier']):
    ax2.text(bar.get_width()+0.2,bar.get_y()+bar.get_height()/2,f'{val:.1f} ({tier})',va='center',fontsize=8)
ax2.set_facecolor('white')

ax3=fig.add_subplot(gs[1,2]); ax3.set_facecolor('white')
ax3.barh(cp['carrier'],cp['on_time_pct'],
    color=[C['green'] if v>=60 else C['amber'] if v>=45 else C['red'] for v in cp['on_time_pct']],height=0.65)
ax3.axvline(cp['on_time_pct'].mean(),color=C['gray'],linestyle='--',linewidth=1.2,alpha=0.7)
ax3.set_xlabel('On-Time Rate (%)'); ax3.set_title('On-Time Rate by Carrier',fontsize=11,fontweight='bold',pad=8)
ax3.set_facecolor('white')

monthly_exec=df.groupby('month').agg(shipments=('shipment_id','count'),
    late=('is_late','sum'),avg_cost=('freight_cost_usd','mean'))\
    .assign(late_rate=lambda x:(x['late']/x['shipments']*100).round(1),
            ops_health=lambda x:(100-x['late']/x['shipments']*100).round(1))\
    .reset_index().sort_values('month')

ax4=fig.add_subplot(gs[2,:]); ax4.set_facecolor('white')
ax4b=ax4.twinx()
x=range(len(monthly_exec))
ax4.fill_between(x,monthly_exec['ops_health'],alpha=0.15,color=C['green'])
ax4.plot(x,monthly_exec['ops_health'],color=C['green'],linewidth=2.5,marker='o',markersize=4,label='Ops Health Score')
ax4b.bar(x,monthly_exec['shipments'],color=C['blue'],alpha=0.2,label='Monthly Shipments')
ax4.set_ylabel('Ops Health Score',color=C['green']); ax4b.set_ylabel('Shipments',color=C['blue'])
ax4.set_title('Monthly Ops Health vs Shipment Volume',fontsize=12,fontweight='bold',pad=8)
ax4.set_xticks(x[::2]); ax4.set_xticklabels(monthly_exec['month'].iloc[::2],rotation=35,ha='right',fontsize=8)
ax4.grid(axis='y',alpha=0.2); ax4.set_facecolor('white')
l1,lb1=ax4.get_legend_handles_labels(); l2,lb2=ax4b.get_legend_handles_labels()
ax4.legend(l1+l2,lb1+lb2,fontsize=9,loc='upper left')

fig.suptitle('Finance Risk Monitoring — Carrier Benchmarking Dashboard',fontsize=14,fontweight='bold',y=0.98)
fig.text(0.99,0.01,'Nishit Patel | AmEx Data Governance Project',ha='right',fontsize=8,color=C['gray'])
plt.savefig('dashboard1_carrier_benchmark.png',dpi=150,bbox_inches='tight')
plt.show()
print('Chart saved: dashboard1_carrier_benchmark.png')
# CELL 7: DASHBOARD 2 — Cost Anomaly Heatmap
fig2=plt.figure(figsize=(20,12)); fig2.patch.set_facecolor('#F8F9FA')
gs2=gridspec.GridSpec(2,2,figure=fig2,hspace=0.45,wspace=0.3)

pivot=df.groupby(['carrier','month'])['freight_cost_usd'].mean().round(1)\
    .reset_index().pivot(index='carrier',columns='month',values='freight_cost_usd').fillna(0)

ax5=fig2.add_subplot(gs2[0,:])
cmap=LinearSegmentedColormap.from_list('cost',['#EAF3DE','#FAEEDA','#EF9F27','#E24B4A','#791F1F'])
im=ax5.imshow(pivot.values,cmap=cmap,aspect='auto',interpolation='nearest')
ax5.set_xticks(range(len(pivot.columns))); ax5.set_xticklabels(list(pivot.columns),rotation=45,ha='right',fontsize=7)
ax5.set_yticks(range(len(pivot.index))); ax5.set_yticklabels(list(pivot.index),fontsize=10)
ax5.set_title('Freight Cost Heatmap — Carrier x Month (Cost Anomaly Detection)',fontsize=13,fontweight='bold',pad=10)
for i in range(len(pivot.index)):
    for j in range(len(pivot.columns)):
        v=pivot.values[i,j]
        if v>0: ax5.text(j,i,f'${v:.0f}',ha='center',va='center',fontsize=7,
            color='white' if v>160 else '#2C2C2A',fontweight='bold')
plt.colorbar(im,ax=ax5,pad=0.01,shrink=0.9).set_label('Avg Freight Cost ($)',fontsize=9)

ax6=fig2.add_subplot(gs2[1,0])
anom_count=monthly_cost[monthly_cost['anomaly_flag'].isin(['CRITICAL SPIKE','Anomaly — Review'])]\
    .groupby('carrier')['anomaly_flag'].count().sort_values(ascending=True)
ax6.barh(anom_count.index,anom_count.values,
    color=[C['red'] if v>=3 else C['amber'] for v in anom_count.values],height=0.65)
ax6.set_xlabel('Anomaly Months Count'); ax6.set_title('Cost Anomaly Frequency by Carrier',fontsize=11,fontweight='bold',pad=6)
ax6.set_facecolor('white')

ax7=fig2.add_subplot(gs2[1,1])
worst5=monthly_cost.groupby('carrier')['cost_change_pct'].apply(lambda x:x.abs().mean()).nlargest(5).index
pal=[C['red'],C['amber'],C['purple'],C['blue'],C['green']]
for i,v in enumerate(worst5):
    sub=monthly_cost[monthly_cost['carrier']==v].dropna(subset=['cost_change_pct']).sort_values('month')
    ax7.plot(range(len(sub)),sub['cost_change_pct'].values,marker='o',markersize=4,linewidth=1.8,label=v,color=pal[i])
ax7.axhline(10,color=C['amber'],linestyle='--',linewidth=1,alpha=0.7,label='Anomaly +10%')
ax7.axhline(-10,color=C['blue'],linestyle='--',linewidth=1,alpha=0.7)
ax7.axhline(0,color=C['gray'],linewidth=0.8,alpha=0.5)
ax7.set_ylabel('MoM Cost Change (%)'); ax7.set_title('Cost Volatility — Top 5 Carriers',fontsize=11,fontweight='bold',pad=6)
ax7.legend(fontsize=8); ax7.grid(axis='y',alpha=0.2); ax7.set_facecolor('white')

fig2.suptitle('Cost Anomaly Detection — Early Warning Indicators',fontsize=14,fontweight='bold',y=0.99)
fig2.text(0.99,0.01,'Nishit Patel | AmEx Data Governance Project',ha='right',fontsize=8,color=C['gray'])
plt.savefig('dashboard2_cost_anomaly_heatmap.png',dpi=150,bbox_inches='tight')
plt.show()
print('Chart saved: dashboard2_cost_anomaly_heatmap.png')
# CELL 8: Export automated Excel report
from datetime import datetime
report_date=datetime.now().strftime('%Y-%m-%d')
with pd.ExcelWriter(f'finance_risk_report_{report_date}.xlsx',engine='openpyxl') as writer:
    pd.DataFrame(list(kpis.items()),columns=['KPI','Value']).to_excel(writer,sheet_name='KPI_Summary',index=False)
    carrier_perf.to_excel(writer,sheet_name='Carrier_Benchmark',index=False)
    monthly_exec.to_excel(writer,sheet_name='Monthly_Ops',index=False)
    anomalies.to_excel(writer,sheet_name='Cost_Anomalies',index=False)
    monthly_cost.to_excel(writer,sheet_name='MoM_Cost_Tracker',index=False)
print(f'Excel report saved: finance_risk_report_{report_date}.xlsx')
# Download the file
files.download(f'finance_risk_report_{report_date}.xlsx')
files.download('dashboard1_carrier_benchmark.png')
files.download('dashboard2_cost_anomaly_heatmap.png')
print('All files downloaded to your computer!')
