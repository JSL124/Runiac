export type TeamMember = {
  name: string;
  role: string;
  bio: string;
  photo: string;
  github?: string;
  linkedin?: string;
  email?: string;
};

export type Supervisor = {
  name: string;
  role: string;
  email: string;
  bio: string;
};

export const TEAM_MEMBERS: TeamMember[] = [
  {
    name: "Lee Jinseo",
    role: "Project Manager",
    bio: "Leads project planning, documentation quality, sprint coordination, and the product direction that keeps Runiac focused on beginner consistency.",
    photo: "/images/team/lee-jinseo.jpg",
    github: "https://github.com/JSL124",
    linkedin:
      "https://www.linkedin.com/in/jinseo-lee-58b255341/?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=ios_app",
    email: "jason2188@naver.com",
  },
  {
    name: "Kaif Lim Er",
    role: "Mobile Frontend Developer",
    bio: "Builds the Flutter mobile interface, GPS tracking flow, and map-based experience for a clear first-run journey.",
    photo: "/images/team/kaif-lim-er.jpg",
    github: "https://github.com/cookiemonztar2-design",
    linkedin: "https://sg.linkedin.com/in/kaif-lim-82a012227",
    email: "Kaif.2001@yahoo.com",
  },
  {
    name: "Kenji Yeo",
    role: "Backend Developer",
    bio: "Develops Firebase Cloud Functions, authentication flow, notifications, and backend logic that support reliable run tracking.",
    photo: "/images/team/kenji-yeo.png",
    github: "https://github.com/batokok",
    linkedin:
      "https://www.linkedin.com/in/kenji-y-808149118?utm_source=share_via&utm_content=profile&utm_medium=member_ios",
    email: "Kenjiyeo0@gmail.com",
  },
  {
    name: "Liu Zhihui",
    role: "Database & Data Engineer",
    bio: "Designs Firestore data models, XP records, leaderboard aggregation, and the activity data structure behind Runiac progress.",
    photo: "/images/team/liuzhihui.png",
    github: "https://github.com/LZH051",
    linkedin: "https://www.linkedin.com/in/zhihui-liu-301b783bb",
    email: "1789511934@qq.com",
  },
  {
    name: "Konada Obadiah Nahshon",
    role: "UI/UX Designer & QA Lead",
    bio: "Designs beginner-friendly user flows, wireframes, usability testing, and QA checks for the Runiac experience.",
    photo: "/images/team/konada-obadiah-nahshon.png",
    github: "https://github.com/nahshonn",
    linkedin: "https://www.linkedin.com/in/obadiahnahshon",
    email: "obadiahnahshon@gmail.com",
  },
];

export const PROJECT_SUPERVISOR: Supervisor = {
  name: "Ee Kiam Keong",
  role: "Project Supervisor",
  email: "kkeesg@yahoo.com.sg",
  bio: "Provides guidance and oversight for the Runiac Final Year Project.",
};
