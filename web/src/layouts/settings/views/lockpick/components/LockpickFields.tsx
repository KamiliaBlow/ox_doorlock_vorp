import { useSetters, useStore } from '../../../../../store';
import { Group, NumberInput, Switch, Text } from '@mantine/core';
import { useState, useEffect } from 'react';

const LockpickFields: React.FC = () => {
  const currentData = useStore((state) => state.lockpickDifficulty) as any;
  const setLockpickFields = useSetters((setter) => setter.setLockpickDifficulty);

  const [difficulty, setDifficulty] = useState<number>(2);
  
  // Локальное состояние переключателя: true = ВКЛЮЧЕН, false = ВЫКЛЮЧЕН
  const [arePinsRaised, setArePinsRaised] = useState<boolean>(true);

  // Синхронизация при загрузке
  useEffect(() => {
    if (typeof currentData === 'object' && !Array.isArray(currentData)) {
      setDifficulty(currentData.difficulty ?? 2);
      
      // Если в базе false (пины опущены), то переключатель ВКЛ (true)
      setArePinsRaised(currentData.lockpickAreaSize !== true);
    }
  }, [currentData]);

  // Функция обновления общего хранилища
  const updateStore = () => {
    setLockpickFields({
      difficulty: difficulty,
      // ИСПРАВЛЕНИЕ ОШИБКИ 1: Используем 'as any', чтобы обойти проверку старых типов хранилища
      lockpickAreaSize: !arePinsRaised,
    } as any); 
  };

  // ИСПРАВЛЕНИЕ ОШИБКИ 2: Принимаем number | undefined, как требует Mantine
  const handleDifficultyChange = (value: number | undefined) => {
    // Если значение не определено, ничего не делаем
    if (value === undefined) return;
    
    const num = Number(value);
    
    if (!isNaN(num) && num >= 1 && num <= 4) {
      setDifficulty(num);
      updateStore();
    }
  };

  const handleSwitchChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setArePinsRaised(event.currentTarget.checked);
    updateStore();
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
        />
      </div>

      <div style={{ width: '48%', display: 'flex', alignItems: 'center', justifyContent: 'flex-end' }}>
        <Switch
          label="Are some pins raised?"
          description="Less complexity, more raised"
          checked={arePinsRaised}
          onChange={handleSwitchChange}
          size="md"
        />
      </div>
    </Group>
  );
};

export default LockpickFields;