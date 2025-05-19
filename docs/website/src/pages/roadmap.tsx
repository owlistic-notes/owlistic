import Layout from '@theme/Layout';
import { JSX } from 'react';
import { mdiPartyPopper } from '@mdi/js';
import { Item, Timeline } from '../components/RoadmapFeatures/timeline';

const releases = {
    'v0.1.0': new Date(2025, 5, 19),
} as const;

const title = 'Roadmap';
const description = 'A list of future plans and goals, as well as past achievements and milestones.';

const withLanguage = (date: Date) => (language: string) => date.toLocaleDateString(language);

type Base = { icon: string; iconColor?: React.CSSProperties['color']; title: string; description: string };
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
        icon: mdiPartyPopper,
        iconColor: 'deeppink',
        title: 'First beta release',
        description: 'First Owlistic beta version.',
        release: 'v0.1.0',
    }),
    {
        icon: mdiPartyPopper,
        iconColor: 'deeppink',
        title: 'First commit',
        description: 'First commit on GitHub, Owlistic is born.',
        getDateLabel: withLanguage(new Date(2025, 4, 14)),
    },
];

export default function RoadmapPage(): JSX.Element {
    return (
        <Layout title={title} description={description}>
            <section className="my-8">
                <h1 className="md:text-6xl text-center mb-10 text-immich-primary dark:text-immich-dark-primary px-2">
                    {title}
                </h1>
                <p className="text-center text-xl px-2">{description}</p>
                <div className="flex justify-around mt-8 w-full max-w-full">
                    <Timeline items={[...roadmap, ...milestones]} />
                </div>
            </section>
        </Layout>
    );
}