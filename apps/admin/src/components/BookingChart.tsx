import type { Row } from "../data";
export function WeeklyChart({ data, en }: { data: Row[]; en: boolean }) {
  const max = Math.max(1, ...data.map((x) => Number(x.count)));
  const points = data
    .map((x, i) => `${30 + i * 80},${160 - (Number(x.count) / max) * 115}`)
    .join(" ");
  return (
    <div className="chart">
      <svg
        viewBox="0 0 560 205"
        role="img"
        aria-label={en ? "Weekly booking count" : "عدد الحجوزات الأسبوعي"}
      >
        <defs>
          <linearGradient id="area" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#149984" stopOpacity=".22" />
            <stop offset="100%" stopColor="#149984" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[45, 85, 125, 165].map((y) => (
          <line
            key={y}
            x1="25"
            x2="535"
            y1={y}
            y2={y}
            stroke="#edf1f0"
            strokeDasharray="4 5"
          />
        ))}
        {data.length > 0 && (
          <>
            <polygon
              points={`30,165 ${points} ${30 + (data.length - 1) * 80},165`}
              fill="url(#area)"
            />
            <polyline
              points={points}
              fill="none"
              stroke="#168c7b"
              strokeWidth="3"
              strokeLinejoin="round"
            />
            {data.map((x, i) => (
              <g key={i}>
                <circle
                  cx={30 + i * 80}
                  cy={160 - (Number(x.count) / max) * 115}
                  r="4"
                  fill="#fff"
                  stroke="#168c7b"
                  strokeWidth="2"
                />
                <text
                  x={30 + i * 80}
                  y={147 - (Number(x.count) / max) * 115}
                  textAnchor="middle"
                  fill="#35726a"
                  fontSize="11"
                >
                  {String(x.count)}
                </text>
                <text
                  x={30 + i * 80}
                  y="195"
                  textAnchor="middle"
                  fill="#81918c"
                  fontSize="11"
                >
                  {new Date(String(x.date)).toLocaleDateString(
                    en ? "en" : "ar",
                    { weekday: "short", timeZone: "Asia/Hebron" },
                  )}
                </text>
              </g>
            ))}
          </>
        )}
      </svg>
    </div>
  );
}
