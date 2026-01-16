import { useSetters, useStore } from '../../../../../store';
import { Group, NumberInput, Switch, Text } from '@mantine/core';
import { useState, useEffect } from 'react';

const LockpickFields: React.FC = () => {
  const currentDifficulty = useStore((state) => state.lockpickDifficulty) as number;
  const currentAreaSize = useStore((state) => state.lockpickAreaSize) as boolean;

  const setDifficultyValue = useSetters((setter) => setter.setLockpickDifficulty);
  // ИСПРАВЛЕНИЕ ОШИБКИ СБОРКИ: используем корректное имя метода из store
  const setAreaSizeValue = useSetters((setter) => setter.setLockpickAreaSize);

  const [difficulty, setDifficulty] = useState<number>(2);
  const [arePinsRaised, setArePinsRaised] = useState<boolean>(true);

  useEffect(() => {
    // Обработка старых данных при загрузке
    if (typeof currentDifficulty === 'number') {
      setDifficulty(currentDifficulty);
    } else if (typeof currentDifficulty === 'object' && currentDifficulty !== null) {
       // Если вдруг загрузился старый объект, пробуем достать оттуда данные
       // @ts-ignore
       setDifficulty(currentDifficulty.difficulty ?? 2);
    }
    
    setArePinsRaised(currentAreaSize === true);
  }, [currentDifficulty, currentAreaSize]);

  const handleDifficultyChange = (value: number | string | undefined) => {
    if (value === undefined) return;
    const num = Number(value);
    if (!isNaN(num) && num >= 1 && num <= 4) {
      setDifficulty(num);
      // Передаем новое значение 'num' напрямую в хранилище
      setDifficultyValue(num);
    }
  };

  const handleSwitchChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const checked = event.currentTarget.checked;
    setArePinsRaised(checked);
    // Передаем checked напрямую в хранилище
    setAreaSizeValue(checked);
  };

  return (
    <Group mt="md" position="apart" align="center">
      <div style={{ width: '48%' }}>
        <Text weight={500} size="sm" mb={4}>
          Difficulty (1-4)
        </Text>
        <NumberInput
          value={difficulty}
          onChange={handleDifficultyChange}
          min={1}
          max={4}
          step={1}
          placeholder="2"
          description="1 = Easy, 2 = Normal, 3= Hard, 4= Master"
        />
      </div>

      <div style={{ width: '48%', display: 'flex', alignItems: 'center', justifyContent: 'flex-end' }}>
        <Switch
          label="Are all pins active?"
          checked={arePinsRaised}
          onChange={handleSwitchChange}
          size="md"
        />
      </div>
    </Group>
  );
};

export default LockpickFields;