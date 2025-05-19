import type { ReactNode } from 'react';
import * as mdiIcons from '@mdi/js';
import { Item, Timeline } from '../components/RoadmapFeatures/timeline';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

const releases = {
    'v0.1.0': new Date(2025, 5, 19),
} as const;

const title = 'Roadmap';
const description = 'A list of future plans and goals, as well as past achievements and milestones.';

const withLanguage = (date: Date) => (language: string) => date.toLocaleDateString(language);

type Base = {
    icon: string; iconColor?: React.CSSProperties['color']; title: string; description: string
};

const withRelease = ({
    icon,
    iconColor,
    title,
    description,
    release: version,
}: Base & { release: keyof typeof releases }) => {
    return {
        icon,
        iconColor: iconColor ?? 'gray',
        title,
        description,
        link: {
            url: `https://github.com/owlistic-notes/owlistic/releases/tag/${version}`,
            text: version,
        },
        getDateLabel: withLanguage(releases[version]),
    };
};

const roadmap: Item[] = [];

const milestones: Item[] = [
    withRelease({
        icon: mdiIcons.mdiRocketLaunch,
        iconColor: 'darkorange',
        title: 'First beta release',
        description: 'First Owlistic beta version.',
        release: 'v0.1.0',
    }),
    {
        icon: mdiIcons.mdiPartyPopper,
        iconColor: 'deeppink',
        title: 'First commit',
        description: 'First commit on GitHub, Owlistic is born.',
        getDateLabel: withLanguage(new Date(2025, 4, 14)),
    },
];

function RoadmapHeader() {
    return (
    <header>
        <Heading as="h1" className="hero__title">
            Roadmap and Milestones
        </Heading>
    </header>
    );
}

export default function RoadmapPage(): ReactNode {
    return (
        <Layout title={title} description={description}>
            <RoadmapHeader />
            <div className="container">
                <Timeline items={[...milestones, ...roadmap]} />
            </div>
        </Layout>
    );
}